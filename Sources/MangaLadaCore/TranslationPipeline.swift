import Foundation

public struct TranslationProgress: Equatable, Sendable {
    public let provider: TranslationProvider
    public let completed: Int
    public let total: Int
    public let isBatch: Bool

    public init(provider: TranslationProvider, completed: Int, total: Int, isBatch: Bool) {
        self.provider = provider
        self.completed = completed
        self.total = total
        self.isBatch = isBatch
    }
}

public struct TranslationPipeline: Sendable {
    private let sourceLanguage: LanguageCode
    private let targetLanguage: LanguageCode
    private let refiner: KoreanTranslationRefiner
    private let progress: (@Sendable (TranslationProgress) async -> Void)?

    public init(
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        refiner: KoreanTranslationRefiner = KoreanTranslationRefiner(),
        progress: (@Sendable (TranslationProgress) async -> Void)? = nil
    ) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.refiner = refiner
        self.progress = progress
    }

    public func translate(
        _ blocks: [TextBlock],
        provider: TranslationProvider,
        configuration: LocalTranslatorConfiguration,
        fallbackTranslator: TextTranslating = GoogleWebTranslator()
    ) async throws -> [TextBlock] {
        let translator = try TranslatorFactory.makeTranslator(
            provider: provider,
            configuration: configuration,
            fallbackTranslator: fallbackTranslator
        )
        let translatedTexts = try await translateTexts(
            blocks.map(\.originalText),
            translator: translator,
            provider: provider,
            maxConcurrentRequests: configuration.maxConcurrentRequests
        )

        return zip(blocks, translatedTexts).map { block, translatedText in
            var translatedBlock = block
            translatedBlock.translatedText = refiner.refine(
                originalText: block.originalText,
                translatedText: translatedText
            )
            return translatedBlock
        }
    }

    private func translateTexts(
        _ texts: [String],
        translator: TextTranslating,
        provider: TranslationProvider,
        maxConcurrentRequests: Int
    ) async throws -> [String] {
        if let batchTranslator = translator as? BatchTextTranslating {
            await progress?(TranslationProgress(provider: provider, completed: 0, total: texts.count, isBatch: true))
            let translated = try await batchTranslator.translate(texts, source: sourceLanguage, target: targetLanguage)
            await progress?(TranslationProgress(provider: provider, completed: texts.count, total: texts.count, isBatch: true))
            return translated
        }

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
                        let translated = try await translator.translate(text, source: source, target: target)
                        return (index, translated)
                    }
                }

                for try await (index, translated) in group {
                    translatedTexts[index] = translated
                    completedCount += 1
                    await progress?(
                        TranslationProgress(
                            provider: provider,
                            completed: completedCount,
                            total: texts.count,
                            isBatch: false
                        )
                    )
                }
            }
        }

        return translatedTexts
    }
}

public enum TranslatorFactory {
    public static func makeTranslator(
        provider: TranslationProvider,
        configuration: LocalTranslatorConfiguration,
        fallbackTranslator: TextTranslating = GoogleWebTranslator()
    ) throws -> TextTranslating {
        switch provider {
        case .ballonsGoogle, .googleWeb:
            return fallbackTranslator
        case .deepl:
            guard let apiKey = configuration.deepl.apiKey else {
                throw TranslationError.missingConfiguration("DeepL API 키가 없습니다.")
            }
            return DeepLTranslator(
                apiKey: apiKey,
                endpoint: configuration.deepl.endpoint,
                context: configuration.deepl.context
            )
        case .papago:
            guard let clientID = configuration.papago.clientID,
                  let clientSecret = configuration.papago.clientSecret else {
                throw TranslationError.missingConfiguration("Papago clientId/clientSecret이 없습니다.")
            }
            return PapagoTranslator(
                clientID: clientID,
                clientSecret: clientSecret,
                endpoint: configuration.papago.endpoint
            )
        case .llm:
            return OpenAICompatibleTranslator(
                apiKey: configuration.llm.apiKey,
                endpoint: configuration.llm.endpoint,
                model: configuration.llm.model
            )
        case .ollama:
            return OllamaTranslator(
                endpoint: configuration.ollama.endpoint,
                model: configuration.ollama.model
            )
        }
    }
}
