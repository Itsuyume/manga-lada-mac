import Foundation

struct MaskedPagePreparation: Sendable {
    let resolver: MaskedContextResolver?
    let session: URLSession

    func prepare(_ blocks: [TextBlock], selectedIDs: Set<UUID>?, configuration: LocalTranslatorConfiguration,
                 previousContext: String, refresh: Bool = false) async throws -> [TextBlock] {
        guard configuration.interpretMaskedText else { return blocks }
        guard let resolver else {
            throw TranslationError.missingConfiguration("문맥 해석 저장소가 연결되지 않았습니다.")
        }
        let model = OllamaConfiguration(endpoint: configuration.ollama.endpoint, model: OllamaConfiguration.visionModel,
                                        retention: configuration.ollama.retention)
        var prepared = blocks
        for index in blocks.indices where selectedIDs?.contains(blocks[index].id) != false {
            prepared[index].maskedTextInterpretation = nil
            let source = blocks[index].originalText
            guard MaskedContextResolution.needsInterpretation(source) else { continue }
            try Task.checkCancellation()
            let neighbors = blocks.indices.filter { $0 != index && abs($0 - index) <= 2 }
                .map { blocks[$0].originalText }.joined(separator: "\n")
            let context = neighbors + "\nPrevious page:\n" + previousContext.suffix(1_000)
            do {
                let normalized = MaskedTextTranslation.normalizedSpelling(source)
                let response = try await resolver.interpret(source: normalized, context: context, configuration: model, session: session, refresh: refresh)
                let interpreted = response.text
                let changed = interpreted != normalized
                prepared[index].originalText = interpreted
                prepared[index].maskedTextInterpretation = MaskedTextInterpretation(japanese: changed ? interpreted : nil,
                    message: changed ? "Qwen 문맥 해석 · 뜻을 확인해주세요" : "가린 단어의 뜻을 확정하지 못했습니다. 원문을 확인해주세요.",
                    usedCachedInterpretation: response.wasCached)
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                prepared[index].maskedTextInterpretation = MaskedTextInterpretation(japanese: nil,
                    message: "문맥 해석 실패 · 가림표 유지: " + String(error.localizedDescription.prefix(240)))
            }
        }
        return prepared
    }

    static func restore(_ translated: [TextBlock], originals: [TextBlock]) throws -> [TextBlock] {
        let byID = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, $0) })
        return try translated.map { block in
            guard let original = byID[block.id] else { throw TranslationSelectionError.missingRegion }
            try MaskedTextTranslation.validateKnownNames(block.translatedText, source: original.originalText)
            var restored = block
            restored.originalText = original.originalText
            restored.maskedTextInterpretation = block.maskedTextInterpretation
            return restored
        }
    }
}
