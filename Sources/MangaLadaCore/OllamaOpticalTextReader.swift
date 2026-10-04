import Foundation

public struct OllamaOpticalTextReader: Sendable {
    private let client: OllamaChatClient
    public init(configuration: OllamaConfiguration = OllamaConfiguration(model: OllamaConfiguration.visionModel), session: URLSession = .shared) {
        client = OllamaChatClient(configuration: configuration, session: session)
    }
    public func recognize(_ image: Data) async throws -> String {
        try await client.validated(
            system: "You transcribe printed Japanese characters exactly. Do not translate or infer plot.",
            user: "Read all printed Japanese text in this crop, top to bottom and right to left. Preserve names. Ignore illustration. Return only {\"text\":\"exact original Japanese\"}.",
            schema: .object(properties: ["text": .string(choices: nil)], required: ["text"]), images: [image], outputTokens: 256) { data in
                struct Response: Decodable { let text: String }
                let value: Response
                do { value = try JSONDecoder().decode(Response.self, from: data) }
                catch { throw TranslationError.invalidPageResponse("장식 글자 OCR 응답이 올바르지 않습니다.") }
                let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, text.count < 200 else { throw TranslationError.invalidPageResponse("장식 글자 OCR 결과가 비어 있거나 너무 깁니다.") }
                return text
            }
    }
}
