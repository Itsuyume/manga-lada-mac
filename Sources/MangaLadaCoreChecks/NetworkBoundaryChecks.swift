import Foundation
import MangaLadaCore

enum NetworkBoundaryChecks {
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        try await checkSelections(session: session)
        try await checkUnselectedLanguageErrors(session: session)
        try await checkMultipleSelectedRegions(session: session)
        let blocks = [TextBlock(box: TextBox(x: 0.2, y: 0.3, width: 0.2, height: 0.3), originalText: "ありがとう")]
        let page = #"{"translations":[{"id":0,"text":"고마워","kind":"dialogue"}]}"#
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(OllamaProbe.self, from: Self.body(request))
            try check(body.model == "qwen3.5:9b" && !body.think && !body.stream && body.format.type == "object", "Local request settings or schema are wrong.")
            let content = "```json\n" + page + "\n```"
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
        let result = try await OllamaPageTranslator(configuration: OllamaConfiguration(model: "qwen3.5:9b"), session: session).translatePage(blocks)
        try check(result[0].translatedText == "고마워" && result[0].box == blocks[0].box, "Local response lost text or geometry.")
        try await checkGemma(blocks, session: session)
        try await checkGemmaValidationRetry(blocks, session: session)
        try await checkValidationRetry(blocks, session: session, validPage: page)
        try await checkMissingFieldRetry(blocks, session: session, validPage: page)
        try await checkIncompleteResponse(blocks, session: session, validPage: page)
        try await checkLocalGuard(blocks, session: session)
        FixtureProtocol.state.install { _ in (503, Data()) }
        do { _ = try await OllamaPageTranslator(session: session).translatePage(blocks); throw BoundaryCheckError.failed("HTTP failure was hidden.") }
        catch TranslationError.httpStatus(503) { }
        FixtureProtocol.state.install { request in
            try check(request.url?.host == "generativelanguage.googleapis.com" && request.url?.query == nil, "Gemini key could leak through URL.")
            try check(request.value(forHTTPHeaderField: "x-goog-api-key") == "fixture-key", "Gemini authentication header is missing.")
            return (200, try JSONEncoder().encode(GeminiReply(candidates: [.init(content: .init(parts: [.init(text: page)]))])))
        }
        let cloud = try await GeminiPageTranslator(configuration: GeminiConfiguration(apiKey: "fixture-key"), session: session).translatePage(blocks)
        try check(cloud[0].translatedText == "고마워", "Gemini response did not map the page.")
        do { _ = try await GeminiPageTranslator(configuration: GeminiConfiguration(), session: session).translatePage(blocks); throw BoundaryCheckError.failed("Empty API key was accepted.") }
        catch TranslationError.missingConfiguration { }
    }
    private static func checkSelections(session: URLSession) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let bounds = TextBox(x: 0.2, y: 0.65, width: 0.4, height: 0.2)
        let effect = TextBlock(box: bounds, originalText: "ゴロゴロ", translatedText: "기존 효과음", confidence: 0.9,
                               sourceIsVertical: true, detectedFontSize: 22, textKind: .soundEffect, rotationDegrees: 8,
                               effectStyleID: "impact", userDefinedBounds: bounds, userDefinedTextKind: true)
        let caption = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.2), originalText: "雷が鳴っている。",
                                translatedText: "사용자가 검수한 천둥 설명", textKind: .caption)
        let blocks = [effect, caption]
        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Invalid or empty selection reached the network.") }
        let empty = try await pipeline.translateSelected([], in: blocks, configuration: LocalTranslatorConfiguration())
        try check(empty == blocks, "Empty selection modified a reviewed page.")
        let blank = try await pipeline.translateSelected([], in: [], configuration: LocalTranslatorConfiguration())
        try check(blank.isEmpty, "Empty page produced regions.")
        do {
            _ = try await pipeline.translateSelected([UUID()], in: blocks, configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Unknown selected ID was accepted.")
        } catch TranslationSelectionError.missingRegion { }
        do {
            _ = try await pipeline.translateSelected([effect.id], in: [effect, effect], configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Duplicate region IDs were accepted.")
        } catch TranslationSelectionError.duplicateRegions { }
        try check(FixtureProtocol.state.count == 0, "Rejected selection had a network side effect.")
        try await checkSelectionCancellation(pipeline: pipeline, blocks: blocks, session: session)
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(GemmaProbe.self, from: Self.body(request))
            try check(body.messages[0].content.contains("[R0] 雷が鳴っている。") && body.messages[0].content.contains("[R1] ゴロゴロ"),
                      "Selected translation lost page context or reading order.")
            let text = "[R0] 모델이 새로 쓴 천둥 설명\n[R1] 우르릉"
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: text))))
        }
        let selected = try await pipeline.translateSelected([effect.id], in: blocks, configuration: LocalTranslatorConfiguration())
        var expected = blocks; expected[0].translatedText = "우르릉"
        try check(selected == expected, "Selected retry changed another draft, metadata or array order.")
        let multiple = try await pipeline.translateSelected(Set(blocks.map(\.id)), in: blocks, configuration: LocalTranslatorConfiguration())
        expected[1].translatedText = "모델이 새로 쓴 천둥 설명"
        try check(multiple == expected, "Multiple selection failed to update only the requested text fields.")
        FixtureProtocol.state.install { _ in (503, Data()) }
        do {
            _ = try await pipeline.translateSelected([effect.id], in: blocks, configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Selected translation hid an HTTP error.")
        } catch TranslationError.httpStatus(503) { }
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 천둥"))))
        }
        do {
            _ = try await pipeline.translateSelected([effect.id], in: blocks, configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Missing selected result was accepted.")
        } catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 2 && blocks == [effect, caption], "Invalid reply retried indefinitely or changed input.")
        try await checkConcurrentSelections(session: session, blocks: blocks)
        try await checkSelectedProviders(session: session, blocks: blocks)
        print("Selected translation passed: full page context, stable order/IDs/styles, unselected drafts preserved, empty/unknown/duplicate IDs, cancellation, HTTP/missing output and concurrent pages")
    }
    private static func checkSelectionCancellation(pipeline: TranslationPipeline, blocks: [TextBlock], session: URLSession) async throws {
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.translateSelected([blocks[0].id], in: blocks, configuration: LocalTranslatorConfiguration())
        }
        do { _ = try await cancelled.value; throw BoundaryCheckError.failed("Cancelled selection started translating.") }
        catch is CancellationError { }
        try check(FixtureProtocol.state.count == 0, "Cancelled selection reached the network.")
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 천둥\n[R1] 우르릉"))))
        }
        let lateCancelled = Task {
            let latePipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean,
                progress: { if $0.completed > 0 { withUnsafeCurrentTask { $0?.cancel() } } }, session: session)
            return try await latePipeline.translateSelected([blocks[0].id], in: blocks, configuration: LocalTranslatorConfiguration())
        }
        do { _ = try await lateCancelled.value; throw BoundaryCheckError.failed("Cancellation after response returned edited text.") }
        catch is CancellationError { }
    }
    private static func checkConcurrentSelections(session: URLSession, blocks: [TextBlock]) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        var catDraft = blocks
        catDraft[1].originalText = "猫が鳴いている。"; catDraft[1].translatedText = "검수한 고양이 설명"
        let cat = catDraft
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(GemmaProbe.self, from: Self.body(request))
            let effect = body.messages[0].content.contains("猫が鳴いている。") ? "골골" : "우르릉"
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 주변 문구\n[R1] " + effect))))
        }
        async let thunderResult = pipeline.translateSelected([blocks[0].id], in: blocks, configuration: LocalTranslatorConfiguration())
        async let catResult = pipeline.translateSelected([cat[0].id], in: cat, configuration: LocalTranslatorConfiguration())
        let (thunder, purring) = try await (thunderResult, catResult)
        try check(thunder[0].translatedText == "우르릉" && purring[0].translatedText == "골골"
                  && thunder[1] == blocks[1] && purring[1] == cat[1], "Concurrent selection mixed page contexts or overwrote reviewed text.")
    }
    private static func checkSelectedProviders(session: URLSession, blocks: [TextBlock]) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let page = #"{"translations":[{"id":0,"text":"새 설명","kind":"dialogue"},{"id":1,"text":"우르릉","kind":"dialogue"}]}"#
        FixtureProtocol.state.install { request in
            try check(String(decoding: Self.body(request), as: UTF8.self).contains("雷が鳴っている。"), "Page provider lost selection context.")
            if request.url?.host == "generativelanguage.googleapis.com" {
                return (200, try JSONEncoder().encode(GeminiReply(candidates: [.init(content: .init(parts: [.init(text: page)]))])))
            }
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: page))))
        }
        let configurations = [LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: "qwen3.5:9b")),
                              LocalTranslatorConfiguration(provider: .geminiFlashLite, gemini: GeminiConfiguration(apiKey: "fixture-key"))]
        var expected = blocks; expected[0].translatedText = "우르릉"
        for configuration in configurations {
            let result = try await pipeline.translateSelected([blocks[0].id], in: blocks, configuration: configuration)
            try check(result == expected, "Page provider overwrote reviewed content or user-selected kind.")
        }
        FixtureProtocol.state.install { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            try check(query == "ゴロゴロ", "Independent text provider sent unselected page content.")
            return (200, Data(#"[[["우르릉","ゴロゴロ",null,null,1]]]"#.utf8))
        }
        let google = try await pipeline.translateSelected([blocks[0].id], in: blocks, configuration: LocalTranslatorConfiguration(provider: .googleWeb))
        try check(google == expected && FixtureProtocol.state.count == 1, "Independent text selection changed other regions or sent excess requests.")
    }
    private static func checkUnselectedLanguageErrors(session: URLSession) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let effect = TextBlock(box: TextBox(x: 0.2, y: 0.6, width: 0.3, height: 0.2), originalText: "ドンドン",
                               translatedText: "기존 효과음", textKind: .soundEffect, effectStyleID: "impact")
        let caption = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.2), originalText: "誰かが扉をたたいている。",
                                translatedText: "검수 완료: 문을 두드린다.", textKind: .caption)
        let blocks = [effect, caption]
        let configurations = [LocalTranslatorConfiguration(),
                              LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: "qwen3.5:9b")),
                              LocalTranslatorConfiguration(provider: .geminiFlashLite, gemini: GeminiConfiguration(apiKey: "fixture-key"))]
        var expected = blocks; expected[0].translatedText = "쿵쿵"
        for invalidText in ["日本語のまま", "문扉", ""] {
            for configuration in configurations {
                FixtureProtocol.state.install { request in
                    try check(String(decoding: Self.body(request), as: UTF8.self).contains(caption.originalText), "Selection lost the original page context.")
                    let page = #"{"translations":[{"id":0,"text":"\#(invalidText)","kind":"caption"},{"id":1,"text":"쿵쿵","kind":"soundEffect"}]}"#
                    if configuration.provider == .geminiFlashLite {
                        return (200, try JSONEncoder().encode(GeminiReply(candidates: [.init(content: .init(parts: [.init(text: page)]))])))
                    }
                    let content = configuration.ollama.isTranslationSpecialist ? "[R0] \(invalidText)\n[R1] 쿵쿵" : page
                    return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
                }
                let selected = try await pipeline.translateSelected([effect.id], in: blocks, configuration: configuration)
                try check(selected == expected && FixtureProtocol.state.count == 1,
                          "An unused context translation blocked the selected result, caused a retry, or changed the reviewed caption.")
                do {
                    _ = try await pipeline.translateSelected([caption.id], in: blocks, configuration: configuration)
                    throw BoundaryCheckError.failed("Invalid text was accepted when its region was selected.")
                } catch TranslationError.invalidPageResponse { }
                do {
                    _ = try await pipeline.translate(blocks, configuration: configuration)
                    throw BoundaryCheckError.failed("Full-page translation skipped a required language check.")
                } catch TranslationError.invalidPageResponse { }
                try check(blocks == [effect, caption], "Rejected translation mutated the input page.")
            }
        }
        print("Selected language validation passed: unused Japanese/Chinese/empty output ignored, selected and full-page errors rejected, reviewed text preserved")
    }
    private static func checkMultipleSelectedRegions(session: URLSession) async throws {
        let caption = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.1), originalText: "雨が降っている。",
                                translatedText: "직접 검수한 비 설명", textKind: .caption)
        let first = TextBlock(box: TextBox(x: 0.6, y: 0.5, width: 0.2, height: 0.1), originalText: "ザアア", textKind: .soundEffect)
        let second = TextBlock(box: TextBox(x: 0.2, y: 0.7, width: 0.2, height: 0.1), originalText: "カチッ", textKind: .soundEffect)
        let blocks = [second, caption, first]
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 日本語\n[R1] 쏴아아\n[R2] 딸깍"))))
        }
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let result = try await pipeline.translateSelected([first.id, second.id], in: blocks, configuration: LocalTranslatorConfiguration())
        var expected = blocks; expected[0].translatedText = "딸깍"; expected[2].translatedText = "쏴아아"
        try check(result == expected && FixtureProtocol.state.count == 1, "Multiple selected IDs lost their reading-order mapping or preserved caption.")
    }
    private static func checkGemma(_ blocks: [TextBlock], session: URLSession) async throws {
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(GemmaProbe.self, from: Self.body(request))
            try check(body.model == "translategemma:12b" && body.messages.count == 1 && body.messages[0].role == "user",
                      "Translation specialist did not use its single-user-message contract.")
            try check(body.format == nil && body.think == nil, "Translation specialist received unsupported JSON/reasoning settings.")
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 고마워"))))
        }
        let result = try await OllamaPageTranslator(session: session).translatePage(blocks)
        try check(result[0].translatedText == "고마워" && result[0].id == blocks[0].id, "Specialist response lost region identity.")
    }
    private static func checkValidationRetry(_ blocks: [TextBlock], session: URLSession, validPage: String) async throws {
        let model = OllamaConfiguration(model: "qwen3.5:9b")
        FixtureProtocol.state.install { _ in
            let content = FixtureProtocol.state.count == 1 ? #"{"translations":[]}"# : validPage
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
        let result = try await OllamaPageTranslator(configuration: model, session: session).translatePage(blocks)
        try check(result[0].translatedText == "고마워" && FixtureProtocol.state.count == 2, "Invalid model reply was not corrected once.")
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: #"{"translations":[]}"#))))
        }
        do { _ = try await OllamaPageTranslator(configuration: model, session: session).translatePage(blocks); throw BoundaryCheckError.failed("Repeated invalid reply was hidden.") }
        catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 2, "Invalid reply was retried without a bound.")
    }
    private static func checkGemmaValidationRetry(_ blocks: [TextBlock], session: URLSession) async throws {
        FixtureProtocol.state.install { _ in
            let content = FixtureProtocol.state.count == 1 ? "[R0] ありがとう (고마워)" : "[R0] 고마워"
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
        let result = try await TranslateGemmaPageTranslator(session: session).translatePage(blocks)
        try check(result[0].translatedText == "고마워" && FixtureProtocol.state.count == 2, "Bilingual specialist reply was not corrected once.")
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] ありがとう (고마워)"))))
        }
        do { _ = try await TranslateGemmaPageTranslator(session: session).translatePage(blocks); throw BoundaryCheckError.failed("Bilingual reply was accepted.") }
        catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 2, "Specialist retry was unbounded.")
    }
    private static func checkLocalGuard(_ blocks: [TextBlock], session: URLSession) async throws {
        let endpoint = URL(string: "https://example.invalid/api/chat")!
        for configuration in [OllamaConfiguration(endpoint: endpoint), OllamaConfiguration(model: "qwen3.5:cloud")] {
            do { _ = try await OllamaPageTranslator(configuration: configuration, session: session).translatePage(blocks); throw BoundaryCheckError.failed("Local mode allowed a remote request.") }
            catch TranslationError.missingConfiguration { }
        }
    }
    private static func checkIncompleteResponse(_ blocks: [TextBlock], session: URLSession, validPage: String) async throws {
        let completions: [(Bool?, String?)] = [(true, "length"), (false, nil), (nil, nil)]
        for model in ["translategemma:12b", "qwen3.5:9b"] {
            let content = model.hasPrefix("translategemma") ? "[R0] 고마워" : validPage
            for (done, reason) in completions {
                FixtureProtocol.state.install { _ in
                    let reply = ChatReply(message: Message(role: "assistant", content: content), done: done, done_reason: reason)
                    return (200, try JSONEncoder().encode(reply))
                }
                do {
                    _ = try await OllamaPageTranslator(configuration: OllamaConfiguration(model: model), session: session).translatePage(blocks)
                    throw BoundaryCheckError.failed("Unfinished model output was accepted as a complete translation.")
                } catch TranslationError.invalidPageResponse { }
                try check(FixtureProtocol.state.count == 1, "Incomplete generation repeated the same request budget.")
            }
        }
    }
    private static func checkMissingFieldRetry(_ blocks: [TextBlock], session: URLSession, validPage: String) async throws {
        FixtureProtocol.state.install { request in
            if FixtureProtocol.state.count == 1 {
                let content = #"{"translations":[{"id":0,"text":"고마워"}]}"#
                return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
            }
            let body = try JSONDecoder().decode(OllamaProbe.self, from: Self.body(request))
            try check(body.messages.last?.content.contains("translations[0].kind") == true,
                      "The retry did not tell the model which required field to restore.")
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: validPage))))
        }
        let result = try await OllamaPageTranslator(configuration: OllamaConfiguration(model: "qwen3.5:9b"), session: session).translatePage(blocks)
        try check(result[0].translatedText == "고마워" && result[0].textKind == .dialogue && FixtureProtocol.state.count == 2,
                  "A missing classification did not recover with one targeted retry.")
    }
    private static func body(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { throw BoundaryCheckError.failed("No request body.") }
        stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count < 0 { throw BoundaryCheckError.failed("Cannot read request body.") }
            if count == 0 { break }; data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw BoundaryCheckError.failed(message) } }
    private struct OllamaProbe: Decodable { let model: String; let think: Bool; let stream: Bool; let format: Schema; let messages: [Message]; struct Schema: Decodable { let type: String } }
    private struct Message: Codable { let role: String; let content: String }
    private struct GemmaProbe: Decodable {
        let model: String; let messages: [UserMessage]; let format: String?; let think: Bool?
        struct UserMessage: Decodable { let role: String; let content: String }
    }
    private struct ChatReply: Encodable {
        let message: Message
        var done: Bool? = true
        var done_reason: String? = "stop"
    }
    private struct GeminiReply: Encodable {
        let candidates: [Candidate]
        struct Candidate: Encodable { let content: Content }
        struct Content: Encodable { let parts: [Part] }
        struct Part: Encodable { let text: String }
    }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = FixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.state.respond(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
private final class FixtureState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private let lock = NSLock(); private var handler: Handler?; private var requests = 0
    var count: Int { lock.withLock { requests } }
    func install(_ handler: @escaping Handler) { lock.withLock { self.handler = handler; requests = 0 } }
    func respond(_ request: URLRequest) throws -> (Int, Data) {
        guard let handler = lock.withLock({ requests += 1; return handler }) else { throw BoundaryCheckError.failed("Missing network fixture.") }
        return try handler(request)
    }
}
private enum BoundaryCheckError: Error { case failed(String) }
