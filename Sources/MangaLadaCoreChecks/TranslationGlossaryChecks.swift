import Foundation
import MangaLadaCore

enum TranslationGlossaryChecks {
    static func run() throws {
        let blocks = [TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.5, height: 0.2), originalText: "Sakura and 星見町")]
        let glossary = try TranslationGlossary().setting(source: " Sakura ", korean: " 사쿠라 ")
            .setting(source: "星見町", korean: "호시미마을").setting(source: "Other", korean: "다른이름")
        let before = blocks
        let context = try glossary.context(for: blocks, previous: "Earlier dialogue")
        try check(context.contains("사쿠라") && context.contains("호시미마을") && !context.contains("다른이름") && blocks == before,
                  "Term context included absent names or modified original regions.")
        let other = [TextBlock(box: blocks[0].box, originalText: "Sakurako is here")]
        try check(try glossary.context(for: other, previous: "keep") == "keep", "A name prefix matched a different Latin name.")
        let kana = try TranslationGlossary().setting(source: "ガイル", korean: "가일")
        let decomposed = [TextBlock(box: blocks[0].box, originalText: "カ\u{3099}イルが来た。")]
        try check(try kana.context(for: decomposed, previous: "").contains("가일"), "Canonically equivalent kana missed the explicit book term.")
        let spaced = try TranslationGlossary().setting(source: "Ann A", korean: "앤 에이")
        try check(try spaced.context(for: [TextBlock(box: blocks[0].box, originalText: "Anna came.")], previous: "keep") == "keep",
                  "Term matching merged distinct names by removing whitespace.")
        let updated = try glossary.setting(source: "SAKURA", korean: "사쿠라짱")
        try check(updated.entries.count == 3 && updated.entries[0].korean == "사쿠라짱", "Updating a case variant duplicated a term.")
        let encoded = try JSONEncoder().encode(updated)
        try check(try JSONDecoder().decode(TranslationGlossary.self, from: encoded) == updated, "Book terms did not round trip.")
        for (source, korean) in [(" ", "이름"), ("name", ""), ("name", "名前"), ("line\nbreak", "이름"), ("name", "word")] {
            do { _ = try TranslationGlossary.Entry(source: source, korean: korean); throw Failure.failed("Invalid term was accepted.") }
            catch TranslationGlossary.Failure.invalidEntry { }
        }
        do {
            _ = try TranslationGlossary(entries: [.init(source: "Name", korean: "이름"), .init(source: "name", korean: "별명")])
            throw Failure.failed("Duplicate case variants were accepted.")
        } catch TranslationGlossary.Failure.duplicateOrTooMany { }
        do {
            _ = try JSONDecoder().decode(TranslationGlossary.self, from: Data(#"{"version":9,"entries":[]}"#.utf8))
            throw Failure.failed("An unknown term-file version was accepted.")
        } catch TranslationGlossary.Failure.unsupportedVersion { }
        let bounded = try glossary.context(for: blocks, previous: String(repeating: "이전 대사 ", count: 1_000))
        try check(bounded.count <= 3_000 && bounded.contains("사쿠라"), "Term records were truncated or exceeded the context budget.")
        var configuration = LocalTranslatorConfiguration()
        let previous = configuration; configuration.terminology = glossary
        try check(!configuration.requiresRetranslation(comparedTo: previous), "A book term change discarded saved pages.")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("term-settings-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        try configuration.save(to: file)
        try check(try LocalTranslatorConfiguration.load(configURL: file, environment: [:]).terminology.entries.isEmpty,
                  "Per-book terms leaked into global settings.")
        print("Glossary checks passed: validation, whole names, relevant/complete bounded records, serialization and global-setting isolation")
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.failed(message) } }
    private enum Failure: Error { case failed(String) }
}

extension NetworkBoundaryChecks {
    static func checkBookTerminologyRequests(session: URLSession) async throws {
        let source = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.3, height: 0.2), originalText: "蒼月が来た。", textKind: .dialogue)
        let neighbor = TextBlock(box: TextBox(x: 0.1, y: 0.5, width: 0.3, height: 0.2), originalText: "明日だよ。",
                                 translatedText: "사용자가 확정한 이웃 문장", textKind: .dialogue)
        let glossary = try TranslationGlossary().setting(source: "蒼月", korean: "소게츠").setting(source: "無関係", korean: "관계없음")
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        for model in ["translategemma:27b", "qwen3.5:9b"] {
            var configuration = LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: model))
            configuration.terminology = glossary
            FixtureProtocol.state.install { request in
                let probe = try JSONDecoder().decode(TermProbe.self, from: body(request))
                let text = probe.messages.last?.content ?? ""
                try check(text.contains("소게츠") && !text.contains("관계없음"), "Relevant book terms did not reach the actual model request.")
                let reply = model.hasPrefix("translategemma") ? "[R0] 소게츠가 왔어.\n[R1] 내일이야."
                    : #"{"translations":[{"id":0,"text":"소게츠가 왔어.","kind":"dialogue"},{"id":1,"text":"내일이야.","kind":"dialogue"}]}"#
                return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: reply))))
            }
            let result = try await pipeline.translateSelected([source.id], in: [source, neighbor], configuration: configuration)
            try check(result[0].translatedText == "소게츠가 왔어." && result[0].originalText == source.originalText && result[1] == neighbor,
                      "Book term translation changed source text, geometry or an unselected review.")
        }
        print("Book term request checks passed: Gemma/JSON HTTP boundaries, unchanged source/neighbor, selected-result identity")
    }
    private struct TermProbe: Decodable { let messages: [Message] }
}
