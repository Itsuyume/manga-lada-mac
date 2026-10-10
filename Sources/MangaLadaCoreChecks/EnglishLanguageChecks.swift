import Foundation
import MangaLadaCore

enum EnglishLanguageChecks {
    static func run() async throws {
        try checkSettings()
        try checkOrderAndEffects()
        try await checkProvidersAndSelection()
        try await checkLongParagraphAndRetry()
        print("English support passed: legacy/settings validation, reading order, effect negatives/repetition, all providers, selected IDs/metadata and Korean response validation")
    }

    private static func checkSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        try check(try LocalTranslatorConfiguration.load(configURL: file, environment: [:]).sourceLanguage == .japanese, "Legacy default changed")
        var english = LocalTranslatorConfiguration(sourceLanguage: .english)
        try check(english.usesPreviousPageContext, "English specialist discarded book context")
        try english.save(to: file)
        try check(try LocalTranslatorConfiguration.load(configURL: file, environment: [:]) == english, "English settings did not round-trip")
        try check(english.requiresRetranslation(comparedTo: LocalTranslatorConfiguration()), "Language change did not refresh the page")
        let data = try Data(contentsOf: file)
        english.sourceLanguage = .korean
        do { try english.save(to: file); throw BoundaryCheckError.failed("Unsupported comic language saved") }
        catch TranslationError.missingConfiguration { }
        try check(try Data(contentsOf: file) == data, "Invalid language overwrote valid settings")
        try Data(#"{"sourceLanguage":"ko"}"#.utf8).write(to: file)
        do { _ = try LocalTranslatorConfiguration.load(configURL: file, environment: [:]); throw BoundaryCheckError.failed("Unsupported language loaded") }
        catch TranslationError.missingConfiguration { }
    }

    private static func checkOrderAndEffects() throws {
        let left = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1), originalText: "HELLO")
        let right = TextBlock(box: TextBox(x: 0.6, y: 0.1, width: 0.2, height: 0.1), originalText: "WORLD")
        try check(MangaReadingOrder.sorted([right, left], sourceLanguage: .english) == [left, right], "English order is not left to right")
        try check(MangaReadingOrder.sorted([left, right]) == [right, left], "Japanese order regressed")
        for text in ["", " ", "AH!", "OH!", "NO!", "CLICK HERE", "BOOMING", "BOOM BANG", "RING ME"] {
            try check(EnglishSoundEffects.translation(for: text) == nil, "Ordinary speech became an effect: \(text)")
        }
        try check(EnglishSoundEffects.translation(for: " boom-boom! ") == "쾅쾅", "Effect repetition/case was lost")
        var effect = left; effect.originalText = "CLICK!"
        let inferred = EnglishSoundEffects.inferKinds([effect])
        try check(inferred[0].textKind == .soundEffect && inferred[0].box == effect.box && inferred[0].originalText == effect.originalText, "Effect inference changed source geometry")
        effect.userDefinedTextKind = true; effect.textKind = .dialogue
        try check(EnglishSoundEffects.inferKinds([effect]) == [effect], "User classification overwritten")
        effect.userDefinedTextKind = nil; effect.textKind = .caption
        try check(EnglishSoundEffects.inferKinds([effect]) == [effect], "Caption overwritten")
        do {
            _ = try MangaNumberedPageResponse.decode("[R0] HELLO", blocks: [left])
            throw BoundaryCheckError.failed("Untranslated English accepted")
        } catch TranslationError.invalidPageResponse { }
    }

    private static func checkProvidersAndSelection() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let left = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1), originalText: "Hello!", fontScale: 1.2)
        let right = TextBlock(box: TextBox(x: 0.6, y: 0.1, width: 0.2, height: 0.1), originalText: "Let's go.", translatedText: "검수한 문구", textKind: .dialogue)
        let blocks = [right, left]
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session).forSourceLanguage(.english)
        var settings = LocalTranslatorConfiguration(sourceLanguage: .english)
        settings.interpretMaskedText = true
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(NetworkBoundaryChecks.GemmaProbe.self, from: NetworkBoundaryChecks.body(request))
            try check(body.messages[0].content.contains("English (en)") && body.messages[0].content.contains("[R0] Hello!")
                      && body.messages[0].content.contains("[R1] Let's go."), "English provider lost language or order")
            return try reply("[R0] 안녕!\n[R1] 가자.")
        }
        let selected = try await pipeline.translateSelected([left.id], in: blocks, configuration: settings)
        var expected = blocks; expected[1].translatedText = "안녕!"; expected[1].textKind = .dialogue
        try check(selected == expected, "English selected retry changed other reviews/order/metadata")
        let effect = TextBlock(box: left.box, originalText: "BOOM BOOM!", textKind: .soundEffect)
        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Known English effect called a model") }
        let fixed = try await pipeline.translate([effect], configuration: settings)
        try check(fixed[0].translatedText == "쾅쾅" && FixtureProtocol.state.count == 0, "Fixed effect missed local routing")
        let empty = try await pipeline.translateSelected([], in: blocks, configuration: settings)
        try check(empty == blocks && FixtureProtocol.state.count == 0, "Empty selection had a side effect")
        let page = #"{"translations":[{"id":0,"text":"안녕!","kind":"dialogue"}]}"#
        FixtureProtocol.state.install { _ in try reply(page) }
        let qwen = try await OllamaPageTranslator(configuration: OllamaConfiguration(model: "qwen3.5:9b"), session: session, sourceLanguage: .english).translatePage([left])
        try check(qwen[0].translatedText == "안녕!", "English Qwen response failed")
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(NetworkBoundaryChecks.GeminiReply(candidates: [.init(content: .init(parts: [.init(text: page)]))])))
        }
        let gemini = try await GeminiPageTranslator(configuration: GeminiConfiguration(apiKey: "fixture-key"), session: session, sourceLanguage: .english).translatePage([left])
        try check(gemini[0].translatedText == "안녕!", "English Gemini response failed")
    }

    private static func reply(_ text: String) throws -> (Int, Data) {
        (200, try JSONEncoder().encode(NetworkBoundaryChecks.ChatReply(message: .init(role: "assistant", content: text))))
    }

    private static func checkLongParagraphAndRetry() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let source = String(repeating: "A long narration continues with its own meaning. ", count: 30)
        let block = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.4), originalText: source, textKind: .caption)
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(NetworkBoundaryChecks.GemmaProbe.self, from: NetworkBoundaryChecks.body(request))
            try check(body.options.num_predict >= source.count * 2, "A single long region retained the tiny region-count output budget")
            try check(body.messages[0].content.contains("The ruler speaks casually; the attendant is deferential."), "Book context was dropped")
            if FixtureProtocol.state.count == 1 { return try reply("[R0] 은빛 호수(銀湖)") }
            return try reply("[R0] 은빛 호수에 관한 긴 나레이션.")
        }
        let translator = TranslateGemmaPageTranslator(session: session, sourceLanguage: .english)
        let translated = try await translator.translatePage([block], previousContext: "The ruler speaks casually; the attendant is deferential.")
        try check(FixtureProtocol.state.count == 2 && translated[0].translatedText == "은빛 호수에 관한 긴 나레이션.", "Invalid mixed-script result was not retried and validated")
        try check(translated[0].id == block.id && translated[0].box == block.box && translated[0].originalText == source,
                  "Length/retry policy changed source identity or geometry")
        FixtureProtocol.state.install { _ in try reply("[R0] unchanged English") }
        do { _ = try await translator.translatePage([block]); throw BoundaryCheckError.failed("Repeated invalid translation was silently saved") }
        catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 2, "Invalid output was retried indefinitely")
    }
    private static func check(_ condition: Bool, _ message: String) throws { try NetworkBoundaryChecks.check(condition, message) }
}
