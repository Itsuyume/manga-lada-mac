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
                                  configuration: LocalTranslatorConfiguration, previousContext: String = "",
                                  refreshMaskedContext: Bool = false) async throws -> [TextBlock] {
        try Task.checkCancellation()
        let ids = Set(blocks.map(\.id))
        guard ids.count == blocks.count else { throw TranslationSelectionError.duplicateRegions }
        guard selectedIDs.isSubset(of: ids) else { throw TranslationSelectionError.missingRegion }
        let selectedIDs = selectedIDs.subtracting(blocks.filter { $0.keepsOriginal == true }.map(\.id))
        guard !selectedIDs.isEmpty else { return blocks }
        let translated = try await translateRequest(blocks.filter { $0.keepsOriginal != true }, selectedIDs: selectedIDs, configuration: configuration,
            translator: nil, previousContext: previousContext, refreshMaskedContext: refreshMaskedContext)
        try Task.checkCancellation()
        var result = blocks
        for index in result.indices where selectedIDs.contains(result[index].id) {
            guard let updated = translated.first(where: { $0.id == result[index].id }) else {
                throw TranslationError.invalidPageResponse("선택한 영역의 번역이 빠졌습니다.")
            }
            try MaskedTextTranslation.validateKnownNames(updated.translatedText, source: result[index].originalText)
            result[index].translatedText = updated.translatedText
            result[index].textKind = updated.textKind
            result[index].maskedTextInterpretation = updated.maskedTextInterpretation
        }
        return result
    }

    public func translate(
        _ blocks: [TextBlock],
        configuration: LocalTranslatorConfiguration,
        translator injectedTranslator: TextTranslating? = nil,
        previousContext: String = "",
        refreshMaskedContext: Bool = false
    ) async throws -> [TextBlock] {
        try Task.checkCancellation()
        guard !blocks.isEmpty else { return [] }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw TranslationSelectionError.duplicateRegions }
        let active = blocks.filter { $0.keepsOriginal != true }
        guard !active.isEmpty else { return blocks }
        let translated = try await translateRequest(active, selectedIDs: nil, configuration: configuration,
            translator: injectedTranslator, previousContext: previousContext, refreshMaskedContext: refreshMaskedContext)
        let restored = try MaskedPagePreparation.restore(translated, originals: active)
        guard active.count != blocks.count else { return restored }
        let byID = Dictionary(uniqueKeysWithValues: restored.map { ($0.id, $0) })
        let ordered = injectedTranslator == nil && configuration.provider != .googleWeb ? MangaReadingOrder.sorted(blocks) : blocks
        return try ordered.map { block in
            if block.keepsOriginal == true { return block }
            guard let updated = byID[block.id] else { throw TranslationSelectionError.missingRegion }
            return updated
        }
    }

    private func translateRequest(_ blocks: [TextBlock], selectedIDs: Set<UUID>?, configuration: LocalTranslatorConfiguration,
                                  translator: TextTranslating?, previousContext: String, refreshMaskedContext: Bool) async throws -> [TextBlock] {
        let requested = selectedIDs ?? Set(blocks.map(\.id))
        let classified = try JapaneseSoundEffectLexicon.bundled().inferKinds(blocks, selectedIDs: requested)
        let maskedIDs = Set(blocks.filter {
            configuration.interpretMaskedText && requested.contains($0.id) && MaskedTextTranslation.requiresContextTranslation($0.originalText)
        }.map(\.id))
        let prepared = try await maskedPreparation.prepare(classified, selectedIDs: selectedIDs, configuration: configuration,
            previousContext: previousContext, refresh: refreshMaskedContext)
        guard !maskedIDs.isEmpty, translator == nil else {
            return try await translatePrepared(prepared, configuration: configuration, translator: translator,
                                               previousContext: previousContext, selectedIDs: selectedIDs)
        }
        let masked = prepared.filter { maskedIDs.contains($0.id) }
        let ordinary = prepared.filter { !maskedIDs.contains($0.id) }
        let ordinaryIDs = requested.subtracting(maskedIDs)
        var translated: [TextBlock] = []
        if !ordinaryIDs.isEmpty {
            translated = try await translatePrepared(ordinary, configuration: configuration, translator: nil,
                previousContext: Self.context(masked, previous: previousContext), selectedIDs: ordinaryIDs)
        }
        var qwen = configuration
        qwen.provider = .ollama; qwen.ollama.model = OllamaConfiguration.visionModel
        // Only masked targets receive numbered output slots; the rest is read-only context.
        let contextual = try await translatePage(masked, configuration: qwen,
            previousContext: Self.context(ordinary, previous: previousContext), selectedIDs: maskedIDs)
        translated += contextual.map { block in
            var updated = block
            let interpretation = block.maskedTextInterpretation
            let expanded = MaskedTextTranslation.modelText(block.originalText)
            updated.maskedTextInterpretation = MaskedTextInterpretation(
                japanese: interpretation?.japanese ?? (interpretation == nil && expanded != block.originalText
                    && !MaskedTextTranslation.hasUnresolvedCircles(expanded) ? expanded : nil),
                message: interpretation?.message ?? "사전으로 확인한 가림표 · Qwen 번역",
                translationModel: qwen.ollama.model, usedCachedInterpretation: interpretation?.usedCachedInterpretation)
            return updated
        }
        let updates = Dictionary(uniqueKeysWithValues: translated.map { ($0.id, $0) })
        return prepared.map { updates[$0.id] ?? $0 }
    }

    private static func context(_ neighbors: [TextBlock], previous: String) -> String {
        previous + "\nSame page, context only (do not translate):\n"
            + MangaReadingOrder.sorted(neighbors).map(\.originalText).joined(separator: "\n")
    }

    private func translatePrepared(_ blocks: [TextBlock], configuration: LocalTranslatorConfiguration,
                                   translator injectedTranslator: TextTranslating?, previousContext: String,
                                   selectedIDs: Set<UUID>?) async throws -> [TextBlock] {
        if injectedTranslator == nil, configuration.provider != .googleWeb {
            return try await translatePage(blocks, configuration: configuration, previousContext: previousContext, selectedIDs: selectedIDs)
        }
        let input = blocks.filter { selectedIDs?.contains($0.id) != false }
        let translator = injectedTranslator ?? TranslatorFactory.makeTranslator(
            configuration: configuration, session: session
        )
        let translatedTexts = try await translateTexts(
            input.map { MaskedTextTranslation.modelText($0.originalText) },
            translator: translator,
            maxConcurrentRequests: configuration.maxConcurrentRequests
        )
        try Task.checkCancellation()

        return try zip(input, translatedTexts).map { block, translatedText in
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
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        let fixedEffects = Dictionary(uniqueKeysWithValues: ordered.compactMap { block -> (UUID, String)? in
            guard block.textKind == .soundEffect, let text = lexicon.translation(for: block.originalText) else { return nil }
            return (block.id, text)
        })
        let count = selectedIDs?.count ?? ordered.count
        await progress?(TranslationProgress(provider: configuration.provider, completed: 0, total: count))
        try Task.checkCancellation()
        let input = ordered.filter { !TextLanguageDetector.isPunctuationOnly($0.originalText) && fixedEffects[$0.id] == nil }
        let selectedWords = selectedIDs.map { $0.intersection(Set(input.map(\.id))) }
        var translated: [TextBlock] = []
        if !input.isEmpty, selectedWords?.isEmpty != true {
            let translator: any MangaPageTranslating = configuration.provider == .ollama
                ? OllamaPageTranslator(configuration: configuration.ollama, session: session, selectedIDs: selectedWords)
                : GeminiPageTranslator(configuration: configuration.gemini, session: session, selectedIDs: selectedWords)
            let context = fixedEffects.isEmpty ? previousContext
                : Self.context(ordered.filter { fixedEffects[$0.id] != nil }, previous: previousContext)
            translated = try await translator.translatePage(input, previousContext: context)
        }
        let result = try ordered.map { block in
            guard selectedIDs?.contains(block.id) != false else { return block }
            if let text = fixedEffects[block.id] {
                var effect = block; effect.translatedText = text
                return effect
            }
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
