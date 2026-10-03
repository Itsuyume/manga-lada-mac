import Foundation

public struct GeminiPageTranslator: MangaPageTranslating {
    private let configuration: GeminiConfiguration
    private let session: URLSession
    public init(configuration: GeminiConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func translatePage(_ blocks: [TextBlock], previousContext: String = "") async throws -> [TextBlock] {
        guard !blocks.isEmpty else { return [] }
        guard !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.missingConfiguration("설정에서 Gemini API 키를 입력해주세요. 로컬 모드는 API 키가 필요 없습니다.")
        }
        guard configuration.model.hasPrefix("gemini-"), configuration.model.contains("flash-lite"),
              configuration.model.range(of: #"^gemini-[a-z0-9.-]+flash-lite[a-z0-9.-]*$"#, options: .regularExpression) != nil,
              !configuration.model.contains("image") else {
            throw TranslationError.missingConfiguration("저가 API 모드는 Gemini Flash-Lite 모델만 지원합니다.")
        }
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(configuration.model):generateContent")!
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(
            systemInstruction: Content(parts: [Part(text: MangaTranslationPrompt.system)]),
            contents: [Content(parts: [Part(text: try MangaTranslationPrompt.user(blocks: blocks, previousContext: previousContext))])],
            generationConfig: GenerationConfig(temperature: 0.15, responseMimeType: "application/json", maxOutputTokens: min(8192, max(1024, blocks.count * 160)))
        ))
        let data = try await TranslationHTTP.data(for: request, session: session)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let content = response.candidates.first?.content else { throw TranslationError.missingTranslatedText }
        let text = content.parts.map(\.text).joined()
        return try MangaPageResponse.decode(ModelJSON.data(from: text), blocks: blocks)
    }

    private struct Part: Codable { let text: String }
    private struct Content: Codable { let parts: [Part] }
    private struct Request: Encodable {
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: GenerationConfig
    }
    private struct GenerationConfig: Encodable {
        let temperature: Double
        let responseMimeType: String
        let maxOutputTokens: Int
    }
    private struct Response: Decodable { let candidates: [Candidate] }
    private struct Candidate: Decodable { let content: Content? }
}
