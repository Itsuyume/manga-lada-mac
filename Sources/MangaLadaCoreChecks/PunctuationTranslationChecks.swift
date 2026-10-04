import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkPunctuationPreservation(session: URLSession) async throws {
        let configurations = [LocalTranslatorConfiguration(),
            LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: "qwen3.5:9b")),
            LocalTranslatorConfiguration(provider: .geminiFlashLite, gemini: GeminiConfiguration(apiKey: "fixture-key")),
            LocalTranslatorConfiguration(provider: .googleWeb)]
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let marks = ["・", "・・・", "…", "！？", " ｢…｣ \n", "—", "ー"]
        let blocks = marks.enumerated().map { index, text in
            let bounds = TextBox(x: 0.2, y: Double(index) * 0.13, width: 0.2, height: 0.1)
            return TextBlock(box: bounds, originalText: text, confidence: 0.9, sourceIsVertical: true,
                             detectedFontSize: 22, textKind: .soundEffect, rotationDegrees: 8,
                             effectStyleID: "impact", userDefinedBounds: bounds, userDefinedTextKind: true)
        }
        var expected = blocks
        for index in expected.indices { expected[index].translatedText = marks[index].trimmingCharacters(in: .whitespacesAndNewlines) }
        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Punctuation-only page contacted a translation service.") }
        for configuration in configurations + [LocalTranslatorConfiguration(provider: .geminiFlashLite)] {
            let result = try await pipeline.translate(blocks, configuration: configuration)
            try check(result == expected, "Punctuation preservation changed content, IDs, geometry or style.")
        }
        try check(FixtureProtocol.state.count == 0, "Punctuation-only pages made unnecessary model requests.")
        try await checkPunctuationCancellation(session: session, blocks: blocks)
        try await checkMixedPunctuation(session: session, configurations: configurations)
        try await checkNonPunctuationRejection(pipeline: pipeline)
        print("Punctuation pipeline passed: zero requests for symbols, mixed/selected mapping, all providers, metadata, cancellation and word/error rejection")
    }

    private static func checkMixedPunctuation(session: URLSession, configurations: [LocalTranslatorConfiguration]) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let caption = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.1), originalText: "寒い。",
                                translatedText: "검수한 추위 설명", textKind: .caption)
        let mark = TextBlock(box: TextBox(x: 0.2, y: 0.4, width: 0.3, height: 0.1), originalText: "．．．！？",
                             translatedText: "사용자가 검수한 기호", textKind: .dialogue)
        let effect = TextBlock(box: TextBox(x: 0.3, y: 0.7, width: 0.4, height: 0.1), originalText: "ガタガタ",
                               translatedText: "검수한 효과음", textKind: .soundEffect, effectStyleID: "impact")
        let blocks = [effect, mark, caption]
        for configuration in configurations {
            FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Selecting punctuation sent surrounding words to the model.") }
            let punctuationOnly = try await pipeline.translateSelected([mark.id], in: blocks, configuration: configuration)
            var expected = blocks; expected[1].translatedText = mark.originalText
            try check(punctuationOnly == expected && FixtureProtocol.state.count == 0, "Symbol selection changed an unrelated review or used the network.")
            for selection: Set<UUID> in [[effect.id], [effect.id, mark.id]] {
                installPunctuationReply(configuration: configuration, captionText: "日本語")
                let selected = try await pipeline.translateSelected(selection, in: blocks, configuration: configuration)
                expected = blocks; expected[0].translatedText = "딱딱"
                if selection.contains(mark.id) { expected[1].translatedText = mark.originalText }
                try check(selected == expected && FixtureProtocol.state.count == 1, "Mixed selection lost IDs, rewrote reviews or made extra requests.")
            }
            installPunctuationReply(configuration: configuration, captionText: "춥다.")
            let full = try await pipeline.translate(blocks, configuration: configuration)
            expected = blocks; expected[0].translatedText = "딱딱"; expected[1].translatedText = mark.originalText; expected[2].translatedText = "춥다."
            if configuration.provider != .googleWeb { expected = MangaReadingOrder.sorted(expected) }
            let count = configuration.provider == .googleWeb ? 2 : 1
            try check(full == expected && FixtureProtocol.state.count == count, "Full page lost reading order, punctuation or region metadata.")
            FixtureProtocol.state.install { _ in (503, Data()) }
            do {
                _ = try await pipeline.translateSelected([effect.id, mark.id], in: blocks, configuration: configuration)
                throw BoundaryCheckError.failed("A lexical translation failure was replaced with original text.")
            } catch TranslationError.httpStatus(503) { }
            try check(FixtureProtocol.state.count == 1 && blocks == [effect, mark, caption], "A failed request retried or mutated the source page.")
        }
    }

    private static func installPunctuationReply(configuration: LocalTranslatorConfiguration, captionText: String) {
        FixtureProtocol.state.install { request in
            if configuration.provider == .googleWeb {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
                try check(query == "寒い。" || query == "ガタガタ", "An independent request sent punctuation to the service.")
                let text = query == "寒い。" ? "춥다." : "딱딱"
                return (200, Data("[[[\"\(text)\",\"\(query!)\",null,null,1]]]".utf8))
            }
            let bodyData = try Self.body(request)
            let bodyText = String(decoding: bodyData, as: UTF8.self)
            try check(bodyText.contains("寒い。") && bodyText.contains("ガタガタ") && !bodyText.contains("．．．！？"),
                      "The page request lost lexical context or included untranslated symbol regions.")
            if configuration.provider == .ollama && configuration.ollama.isTranslationSpecialist {
                let payload = try JSONDecoder().decode(GemmaProbe.self, from: bodyData)
                try check(payload.messages[0].content.contains("[R0] 寒い。") && payload.messages[0].content.contains("[R1] ガタガタ"),
                          "Removing punctuation left gaps in the model's region numbers.")
                return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] \(captionText)\n[R1] 딱딱"))))
            }
            let page = #"{"translations":[{"id":0,"text":"\#(captionText)","kind":"caption"},{"id":1,"text":"딱딱","kind":"soundEffect"}]}"#
            if configuration.provider == .geminiFlashLite {
                return (200, try JSONEncoder().encode(GeminiReply(candidates: [.init(content: .init(parts: [.init(text: page)]))])))
            }
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: page))))
        }
    }

    private static func checkPunctuationCancellation(session: URLSession, blocks: [TextBlock]) async throws {
        for selected in [false, true] {
            for cancelAtStart in [true, false] {
                let cancelled = Task {
                    if cancelAtStart { withUnsafeCurrentTask { $0?.cancel() } }
                    let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean,
                        progress: { if $0.completed > 0 { withUnsafeCurrentTask { $0?.cancel() } } }, session: session)
                    if selected { return try await pipeline.translateSelected([blocks[0].id], in: blocks, configuration: LocalTranslatorConfiguration()) }
                    return try await pipeline.translate(blocks, configuration: LocalTranslatorConfiguration())
                }
                do { _ = try await cancelled.value; throw BoundaryCheckError.failed("Cancelled punctuation work returned a translated page.") }
                catch is CancellationError { }
            }
        }
        try check(FixtureProtocol.state.count == 0, "Cancelled punctuation work made a network request.")
    }

    private static func checkNonPunctuationRejection(pipeline: TranslationPipeline) async throws {
        for source in ["", " \n", "「」", "123", "abc", "パチパチ", "っ", "ッ", "っ12", "ッa", "音…"] {
            FixtureProtocol.state.install { _ in (503, Data()) }
            let block = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2), originalText: source, textKind: .soundEffect)
            do {
                _ = try await pipeline.translate([block], configuration: LocalTranslatorConfiguration())
                throw BoundaryCheckError.failed("A non-punctuation source bypassed translation: \(source).")
            } catch TranslationError.httpStatus(503) { }
            try check(FixtureProtocol.state.count == 1 && block.translatedText.isEmpty, "A failed word translation mutated its input or did not contact the model.")
        }
        let duplicated = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2), originalText: "…")
        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Duplicate region IDs reached the model.") }
        do {
            _ = try await pipeline.translate([duplicated, duplicated], configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Full-page translation accepted duplicate IDs before merging punctuation.")
        } catch TranslationSelectionError.duplicateRegions { }
        try check(FixtureProtocol.state.count == 0, "Duplicate IDs had a network side effect.")
    }
}
