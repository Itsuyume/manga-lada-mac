import Foundation

struct OllamaChatClient: Sendable {
    let configuration: OllamaConfiguration
    let session: URLSession
    func validated<Value: Sendable>(system: String, user: String, schema: ModelResponseSchema, images: [Data] = [],
                                    outputTokens: Int = 2048, decode: @Sendable (Data) throws -> Value) async throws -> Value {
        var instruction = user
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let data = try await send(system: system, user: instruction, schema: schema, images: images, outputTokens: outputTokens)
            do { return try decode(data) }
            catch TranslationError.invalidPageResponse(let detail) {
                guard attempt == 0 else { throw TranslationError.invalidPageResponse(detail) }
                instruction = user + "\nYour previous response failed validation: \(detail). Return a complete valid JSON object matching every required field. Each array item must contain all its fields; never put a single field in a separate item."
            }
        }
        throw TranslationError.invalidResponse
    }
    func send(system: String, user: String, schema: ModelResponseSchema, images: [Data] = [], outputTokens: Int = 2048) async throws -> Data {
        let request = ChatRequest(model: configuration.model,
            messages: [Message(role: "system", content: system, images: nil),
                       Message(role: "user", content: user, images: images.isEmpty ? nil : images.map { $0.base64EncodedString() })],
            stream: false, think: false, format: schema, keep_alive: configuration.retention.rawValue,
            options: Options(temperature: 0.1, num_ctx: 8192, num_predict: min(8192, max(1024, outputTokens))))
        return ModelJSON.data(from: try await response(for: request))
    }
    func text(user: String, outputTokens: Int) async throws -> String {
        try await response(for: ChatRequest(model: configuration.model, messages: [Message(role: "user", content: user, images: nil)],
            stream: false, think: nil, format: nil, keep_alive: configuration.retention.rawValue,
            options: Options(temperature: 0, num_ctx: 4096, num_predict: min(8192, max(256, outputTokens)))))
    }
    private func response(for chat: ChatRequest) async throws -> String {
        guard ["127.0.0.1", "localhost", "::1"].contains(configuration.endpoint.host ?? ""),
              !configuration.model.lowercased().contains("cloud"), !configuration.model.isEmpty else {
            throw TranslationError.missingConfiguration("로컬 모드에서는 Mac 내부의 Ollama와 로컬 모델만 사용할 수 있습니다.")
        }
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: 240)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(chat)
        let data = try await TranslationHTTP.data(for: request, session: session)
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard response.done == true else {
            throw TranslationError.invalidPageResponse("로컬 모델이 응답을 끝까지 생성했는지 확인할 수 없습니다. 이 결과는 저장하지 않았습니다.")
        }
        guard response.doneReason != "length" else {
            throw TranslationError.invalidPageResponse("로컬 모델의 응답이 출력 길이 제한에 걸려 중단되었습니다. 문장이 잘릴 수 있어 이 결과는 저장하지 않았습니다.")
        }
        return response.message.content
    }
    private struct ChatRequest: Encodable {
        let model: String; let messages: [Message]; let stream: Bool; let think: Bool?
        let format: ModelResponseSchema?; let keep_alive: String; let options: Options
    }
    private struct Options: Encodable { let temperature: Double; let num_ctx: Int; let num_predict: Int }
    private struct Message: Codable { let role: String; let content: String; let images: [String]? }
    private struct ChatResponse: Decodable {
        let message: Message
        let done: Bool?
        let doneReason: String?
        enum CodingKeys: String, CodingKey { case message, done; case doneReason = "done_reason" }
    }
}

enum ModelJSON {
    static func data(from response: String) -> Data {
        var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```json\n"), text.hasSuffix("```") { text = String(text.dropFirst(8).dropLast(3)) }
        else if text.hasPrefix("```\n"), text.hasSuffix("```") { text = String(text.dropFirst(4).dropLast(3)) }
        return Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }
}
