import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkMaskedContext(session: URLSession) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("masked-context-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("reuse")
        let configuration = LocalTranslatorConfiguration(interpretMaskedText: true)
        let pipeline = contextPipeline(directory, session: session)
        let block = contextBlock("お○ぎりを食べよう。", y: 0.1)
        let neighbor = contextBlock("海苔で包んでね。", y: 0.5)
        installContextResponse(terms: #"{"terms":[{"masked":"お○ぎり","expanded":"おにぎり"}]}"#,
                               translation: "[R0] 주먹밥을 먹자.\n[R1] discarded")
        let first = try await pipeline.translateSelected([block.id], in: [block, neighbor], configuration: configuration)
        try check(FixtureProtocol.state.count == 2 && first[1] == neighbor, "Interpretation changed unselected text or called extra models.")
        try check(first[0].originalText == block.originalText && first[0].box == block.box && first[0].id == block.id,
                  "Interpretation overwrote OCR source or geometry.")
        try check(first[0].translatedText == "주먹밥을 먹자." && first[0].maskedTextInterpretation?.japanese == "おにぎりを食べよう。",
                  "Validated expansion did not reach Korean translation or review metadata.")
        let cache = directory.appendingPathComponent("masked-context-v1.json")
        let bytes = try Data(contentsOf: cache)
        for translator in [pipeline, contextPipeline(directory, session: session)] {
            let before = FixtureProtocol.state.count
            let repeated = try await translator.translateSelected([block.id], in: [block, neighbor], configuration: configuration)
            var expected = first
            expected[0].maskedTextInterpretation = MaskedTextInterpretation(japanese: first[0].maskedTextInterpretation?.japanese,
                message: first[0].maskedTextInterpretation?.message ?? "", translationModel: OllamaConfiguration.visionModel,
                usedCachedInterpretation: true)
            try check(repeated == expected && FixtureProtocol.state.count == before + 1, "Identical context called Qwen interpretation again or changed output.")
        }
        try check(try Data(contentsOf: cache) == bytes, "A cache hit rewrote interpretation data.")
        var changed = neighbor; changed.originalText = "別の文脈です。"
        let before = FixtureProtocol.state.count
        _ = try await pipeline.translateSelected([block.id], in: [block, changed], configuration: configuration)
        try check(FixtureProtocol.state.count == before + 2, "Interpretation leaked into a different context.")
        var edited = first[0]; edited.originalText = "おにぎりを食べよう。"
        try check(edited.maskedTextInterpretation == nil, "Editing the original retained a stale interpretation.")
        try check(try JSONDecoder().decode(TextBlock.self, from: JSONEncoder().encode(first[0])) == first[0], "Interpretation did not survive storage.")
        try await checkContextRejections(root: root, session: session, configuration: configuration, block: block)
        try await checkContextFastPaths(root: root, session: session, configuration: configuration)
        try await checkContextCacheLimits(root: root, session: session, configuration: configuration)
        print("Masked context passed: local-only interpretation, exact-context disk reuse, no glossary promotion, source/geometry/reviews, malformed replies and visible failures")
    }

    private static func checkContextRejections(root: URL, session: URLSession, configuration: LocalTranslatorConfiguration, block: TextBlock) async throws {
        for (index, terms) in [
            #"{"terms":[{"masked":"お○ぎり","expanded":"おすし"}]}"#,
            #"{"terms":[{"masked":"お○ぎり","expanded":"주먹밥"}]}"#,
            #"{"terms":[{"masked":"ア○ス","expanded":"アイス"}]}"#,
            #"{"terms":[{"masked":"お○ぎり","expanded":"おにぎり"},{"masked":"お○ぎり","expanded":"おにぎり"}]}"#,
            #"{"terms":[{"masked":"お○ぎり","expanded":"お○ぎり"}]}"#,
            "[]"
        ].enumerated() {
            let folder = root.appendingPathComponent("bad-\(index)")
            installContextResponse(terms: terms, translation: "[R0] 오○기리를 먹자.")
            let output = try await contextPipeline(folder, session: session).translate([block], configuration: configuration)
            try check(FixtureProtocol.state.count == 3, "Invalid interpretation did not use exactly one correction attempt.")
            try check(output[0].originalText == block.originalText && output[0].maskedTextInterpretation?.japanese == nil
                      && output[0].maskedTextInterpretation?.message.contains("실패") == true, "Invalid interpretation was silently accepted.")
            try check(!FileManager.default.fileExists(atPath: folder.path), "Rejected interpretation poisoned the cache.")
        }
        let folder = root.appendingPathComponent("corrupt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cache = folder.appendingPathComponent("masked-context-v1.json"), bytes = Data("invalid JSON".utf8)
        try bytes.write(to: cache)
        installContextResponse(terms: #"{"terms":[]}"#, translation: "[R0] 오○기리를 먹자.")
        let corrupt = try await contextPipeline(folder, session: session).translate([block], configuration: configuration)
        try check(FixtureProtocol.state.count == 1 && corrupt[0].maskedTextInterpretation?.message.contains("실패") == true,
                  "Corrupt cache was hidden or triggered inference.")
        try check(try Data(contentsOf: cache) == bytes, "Corrupt cache was overwritten.")
        let cancelled = Task { try await contextPipeline(root.appendingPathComponent("cancelled"), session: session).translate([block], configuration: configuration) }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw BoundaryCheckError.failed("Cancelled interpretation completed.") }
        catch is CancellationError { }
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cancelled").path), "Cancellation wrote cache.")
    }

    private static func checkContextFastPaths(root: URL, session: URLSession, configuration: LocalTranslatorConfiguration) async throws {
        for (source, target) in [("ス○ブラで対戦しよう。", "스매시브라더스로 대전하자."),
                                 ("○○さん", "○○ 씨"), ("二〇二六年", "2026년"), ("Oリング", "O링"),
                                 ("新しいOリング", "새 O링"), ("パッキンOリング", "패킹 O링"), ("血液O型", "혈액 O형")] {
            installContextResponse(terms: #"{"terms":[]}"#, translation: "[R0] " + target)
            let result = try await contextPipeline(root.appendingPathComponent("fast"), session: session)
                .translate([contextBlock(source, y: 0.1)], configuration: configuration)
            let expectedModel = MaskedTextTranslation.requiresContextTranslation(source) ? OllamaConfiguration.visionModel : nil
            try check(FixtureProtocol.state.count == 1 && result[0].translatedText == target
                      && result[0].maskedTextInterpretation?.translationModel == expectedModel,
                      "Known name required interpretation, or a non-mask triggered Qwen.")
        }
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("fast").path), "Fast path wrote a context cache.")
    }

    static func contextPipeline(_ directory: URL, session: URLSession) -> TranslationPipeline {
        TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session,
                            maskedResolver: MaskedContextResolver(directory: directory))
    }
    static func contextBlock(_ source: String, y: Double) -> TextBlock {
        TextBlock(box: TextBox(x: 0.1, y: y, width: 0.3, height: 0.2), originalText: source,
                  translatedText: "기존 검수", textKind: .dialogue, userDefinedTextKind: true)
    }
    static func installContextResponse(terms: String, translation: String) {
        FixtureProtocol.state.install { request in
            let payload = try body(request)
            let probe = try JSONDecoder().decode(ContextProbe.self, from: payload)
            let schema = try JSONDecoder().decode(MaskedRouteProbe.self, from: payload).format
            try check(request.url?.host == "127.0.0.1" && probe.keep_alive == "5m", "Inference left the Mac or changed retention.")
            let content: String
            if schema?.properties.terms != nil { content = terms }
            else if let count = schema?.properties.translations?.maxItems {
                content = try contextPageReply(translation, count: count)
            } else { content = translation }
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
    }
    private static func contextPageReply(_ translation: String, count: Int) throws -> String {
        struct Page: Encodable { let translations: [Entry] }
        struct Entry: Encodable { let id: Int; let text: String; let kind = "dialogue" }
        let texts = translation.components(separatedBy: "\n").prefix(count).map {
            $0.replacingOccurrences(of: #"^\[R\d+\] "#, with: "", options: .regularExpression)
        }
        return String(decoding: try JSONEncoder().encode(Page(translations: texts.enumerated().map { Entry(id: $0.offset, text: $0.element) })), as: UTF8.self)
    }
    private struct ContextProbe: Decodable { let model: String; let keep_alive: String }
}
