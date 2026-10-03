import Foundation
import MangaLadaCore

enum NetworkBoundaryChecks {
    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
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
    private struct OllamaProbe: Decodable { let model: String; let think: Bool; let stream: Bool; let format: Schema; struct Schema: Decodable { let type: String } }
    private struct Message: Encodable { let role: String; let content: String }
    private struct GemmaProbe: Decodable {
        let model: String; let messages: [UserMessage]; let format: String?; let think: Bool?
        struct UserMessage: Decodable { let role: String; let content: String }
    }
    private struct ChatReply: Encodable { let message: Message }
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
