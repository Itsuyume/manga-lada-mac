import Foundation

public struct TranslationProgress: Equatable, Sendable {
    public let provider: TranslationProvider
    public let completed: Int
    public let total: Int

    public init(provider: TranslationProvider, completed: Int, total: Int) {
        self.provider = provider
        self.completed = completed
        self.total = total
    }
}

public struct TranslationPipeline: Sendable {
    private let sourceLanguage: LanguageCode
    private let targetLanguage: LanguageCode
    private let refiner: KoreanTranslationRefiner
    private let progress: (@Sendable (TranslationProgress) async -> Void)?
    private let session: URLSession
    private let maskedPreparation: MaskedPagePreparation

    public init(
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        refiner: KoreanTranslationRefiner = KoreanTranslationRefiner(),
        progress: (@Sendable (TranslationProgress) async -> Void)? = nil,
        session: URLSession = .shared,
        maskedResolver: MaskedContextResolver? = nil
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.refiner = refiner
        self.progress = progress
        self.session = session
        self.maskedPreparation = MaskedPagePreparation(resolver: maskedResolver, session: session)
    }

    /// Uses page context but replaces only selected text, retaining draft order and all metadata.
    public func translateSelected(_ selectedIDs: Set<UUID>, in blocks: [TextBlock],
                                  configuration: LocalTranslatorConfiguration, previousContext: String = "") async throws -> [TextBlock] {
        try Task.checkCancellation()
        let ids = Set(blocks.map(\.id))
        guard ids.count == blocks.count else { throw TranslationSelectionError.duplicateRegions }
        guard selectedIDs.isSubset(of: ids) else { throw TranslationSelectionError.missingRegion }
        guard !selectedIDs.isEmpty else { return blocks }
        // Google translates independent strings; sending surrounding blocks there adds no context.
        let prepared = try await maskedPreparation.prepare(blocks, selectedIDs: selectedIDs, configuration: configuration, previousContext: previousContext)
        let input = configuration.provider == .googleWeb ? prepared.filter { selectedIDs.contains($0.id) } : prepared
        let translated: [TextBlock]
        if configuration.provider == .googleWeb {
            translated = try await translatePrepared(input, configuration: configuration, translator: nil, previousContext: previousContext)
        } else {
            translated = try await translatePage(input, configuration: configuration, previousContext: previousContext, selectedIDs: selectedIDs)
        }
        try Task.checkCancellation()
        var result = blocks
        for index in result.indices where selectedIDs.contains(result[index].id) {
            guard let updated = translated.first(where: { $0.id == result[index].id }) else {
                throw TranslationError.invalidPageResponse("선택한 영역의 번역이 빠졌습니다.")
            }
            try MaskedTextTranslation.validateKnownNames(updated.translatedText, source: result[index].originalText)
            result[index].translatedText = updated.translatedText
            result[index].maskedTextInterpretation = updated.maskedTextInterpretation
        }
        return result
    }

    public func translate(
        _ blocks: [TextBlock],
        configuration: LocalTranslatorConfiguration,
        translator injectedTranslator: TextTranslating? = nil,
        previousContext: String = ""
    ) async throws -> [TextBlock] {
        try Task.checkCancellation()
        guard !blocks.isEmpty else { return [] }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw TranslationSelectionError.duplicateRegions }
        let prepared = try await maskedPreparation.prepare(blocks, selectedIDs: nil, configuration: configuration, previousContext: previousContext)
        let translated = try await translatePrepared(prepared, configuration: configuration, translator: injectedTranslator, previousContext: previousContext)
        return try MaskedPagePreparation.restore(translated, originals: blocks)
    }

    private func translatePrepared(_ blocks: [TextBlock], configuration: LocalTranslatorConfiguration,
                                   translator injectedTranslator: TextTranslating?, previousContext: String) async throws -> [TextBlock] {
        if injectedTranslator == nil, configuration.provider != .googleWeb {
            return try await translatePage(blocks, configuration: configuration, previousContext: previousContext, selectedIDs: nil)
        }
        let translator = injectedTranslator ?? TranslatorFactory.makeTranslator(
            configuration: configuration, session: session
        )
        let translatedTexts = try await translateTexts(
            blocks.map { MaskedTextTranslation.modelText($0.originalText) },
            translator: translator,
            maxConcurrentRequests: configuration.maxConcurrentRequests
        )
        try Task.checkCancellation()

        return try zip(blocks, translatedTexts).map { block, translatedText in
            var translatedBlock = block
            let refined = refiner.refine(
                originalText: block.originalText,
                translatedText: translatedText
            )
            translatedBlock.translatedText = try MaskedTextTranslation.validated(refined, source: block.originalText)
            return translatedBlock
        }
    }

    private func translatePage(_ blocks: [TextBlock], configuration: LocalTranslatorConfiguration,
                               previousContext: String, selectedIDs: Set<UUID>?) async throws -> [TextBlock] {
        let ordered = MangaReadingOrder.sorted(blocks)
        let count = selectedIDs?.count ?? ordered.count
        await progress?(TranslationProgress(provider: configuration.provider, completed: 0, total: count))
        try Task.checkCancellation()
        let input = ordered.filter { !TextLanguageDetector.isPunctuationOnly($0.originalText) }
        let selectedWords = selectedIDs.map { $0.intersection(Set(input.map(\.id))) }
        var translated: [TextBlock] = []
        if !input.isEmpty, selectedWords?.isEmpty != true {
            let translator: any MangaPageTranslating = configuration.provider == .ollama
                ? OllamaPageTranslator(configuration: configuration.ollama, session: session, selectedIDs: selectedWords)
                : GeminiPageTranslator(configuration: configuration.gemini, session: session, selectedIDs: selectedWords)
            translated = try await translator.translatePage(input, previousContext: previousContext)
        }
        let result = try ordered.map { block in
            guard selectedIDs?.contains(block.id) != false else { return block }
            if TextLanguageDetector.isPunctuationOnly(block.originalText) {
                var preserved = block
                preserved.translatedText = block.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                return preserved
            }
            guard let updated = translated.first(where: { $0.id == block.id }) else {
                throw TranslationError.invalidPageResponse("번역한 문구의 영역이 빠졌습니다.")
            }
            return updated
        }
        await progress?(TranslationProgress(provider: configuration.provider, completed: count, total: count))
        try Task.checkCancellation()
        return result
    }

    private func translateTexts(
        _ texts: [String],
        translator: TextTranslating,
        maxConcurrentRequests: Int
    ) async throws -> [String] {
        let concurrency = min(max(maxConcurrentRequests, 1), max(texts.count, 1))
        var translatedTexts = Array(repeating: "", count: texts.count)
        var completedCount = 0

        for chunkStart in stride(from: 0, to: texts.count, by: concurrency) {
            let chunkEnd = min(chunkStart + concurrency, texts.count)
            try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for index in chunkStart..<chunkEnd {
                    let text = texts[index]
                    let source = sourceLanguage
                    let target = targetLanguage
                    group.addTask {
                        try Task.checkCancellation()
                        if TextLanguageDetector.isPunctuationOnly(text) {
                            return (index, text.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        let translated = try await translator.translate(text, source: source, target: target)
                        return (index, translated)
                    }
                }

                for try await (index, translated) in group {
                    translatedTexts[index] = translated
                    completedCount += 1
                    await progress?(
                        TranslationProgress(
                            provider: .googleWeb,
                            completed: completedCount,
                            total: texts.count
                        )
                    )
                }
            }
        }

        return translatedTexts
    }
}

public enum TranslatorFactory {
    public static func makeTranslator(configuration _: LocalTranslatorConfiguration, session: URLSession = .shared) -> TextTranslating {
        GoogleWebTranslator(session: session)
    }
}

public enum TranslationSelectionError: LocalizedError, Equatable {
    case duplicateRegions, missingRegion
    public var errorDescription: String? {
        switch self {
        case .duplicateRegions: "페이지의 영역 번호가 중복되어 선택한 문구를 확인할 수 없습니다."
        case .missingRegion: "선택한 영역이 현재 페이지에 없습니다. 페이지를 다시 열고 선택해주세요."
        }
    }
}
