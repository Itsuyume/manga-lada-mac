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
        configuration: LocalTranslatorConfiguration,
        translator injectedTranslator: TextTranslating? = nil
    ) async throws -> [TextBlock] {
        let translator = injectedTranslator ?? TranslatorFactory.makeTranslator(
            configuration: configuration
        )
        let translatedTexts = try await translateTexts(
            blocks.map(\.originalText),
            translator: translator,
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
                        let translated = try await translator.translate(text, source: source, target: target)
                        return (index, translated)
                    }
                }

                for try await (index, translated) in group {
                    translatedTexts[index] = translated
                    completedCount += 1
                    await progress?(
                        TranslationProgress(
                            provider: .ollama,
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
    public static func makeTranslator(configuration: LocalTranslatorConfiguration) -> TextTranslating {
        OllamaTranslator(
            endpoint: configuration.ollama.endpoint,
            model: configuration.ollama.model
        )
    }
}
