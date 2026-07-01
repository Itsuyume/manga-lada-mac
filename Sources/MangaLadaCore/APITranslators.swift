import Foundation

public struct DeepLTranslator: BatchTextTranslating {
    private let apiKey: String
    private let endpoint: URL
    private let context: String?
    private let session: URLSession

    public init(
        apiKey: String,
        endpoint: URL = DeepLConfiguration.defaultEndpoint,
        context: String? = nil,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.context = context
        self.session = session
    }

    public func translate(_ texts: [String], source: LanguageCode, target: LanguageCode) async throws -> [String] {
        let trimmedTexts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !trimmedTexts.contains(where: \.isEmpty) else {
            throw TranslationError.emptyText
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            DeepLRequest(
                text: trimmedTexts,
                sourceLang: source.deepLCode,
                targetLang: target.deepLCode,
                context: context
            )
        )

        let data = try await validatedData(for: request, session: session)
        let translated = try Self.parseTranslationResponse(data)
        guard translated.count == trimmedTexts.count else {
            throw TranslationError.invalidResponse
        }
        return translated
    }

    public static func parseTranslationResponse(_ data: Data) throws -> [String] {
        let response = try JSONDecoder().decode(DeepLResponse.self, from: data)
        let translations = response.translations
            .map(\.text)
            .map(cleanedTranslation)
        guard !translations.isEmpty, !translations.contains(where: \.isEmpty) else {
            throw TranslationError.missingTranslatedText
        }
        return translations
    }
}

public struct PapagoTranslator: TextTranslating {
    private let clientID: String
    private let clientSecret: String
    private let endpoint: URL
    private let session: URLSession

    public init(
        clientID: String,
        clientSecret: String,
        endpoint: URL = PapagoConfiguration.defaultEndpoint,
        session: URLSession = .shared
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.endpoint = endpoint
        self.session = session
    }

    public func translate(_ text: String, source: LanguageCode, target: LanguageCode) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(clientID, forHTTPHeaderField: "X-NCP-APIGW-API-KEY-ID")
        request.setValue(clientSecret, forHTTPHeaderField: "X-NCP-APIGW-API-KEY")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            ("source", source.rawValue),
            ("target", target.rawValue),
            ("text", trimmed)
        ])

        let data = try await validatedData(for: request, session: session)
        return try Self.parseTranslationResponse(data)
    }

    public static func parseTranslationResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(PapagoResponse.self, from: data)
        let translated = cleanedTranslation(response.message.result.translatedText)
        guard !translated.isEmpty else {
            throw TranslationError.missingTranslatedText
        }
        return translated
    }
}

public struct OpenAICompatibleTranslator: TextTranslating {
    private let apiKey: String?
    private let endpoint: URL
    private let model: String
    private let session: URLSession

    public init(
        apiKey: String? = nil,
        endpoint: URL = LLMConfiguration.defaultEndpoint,
        model: String = LLMConfiguration.defaultModel,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint.normalizedChatCompletionsEndpoint
        self.model = model
        self.session = session
    }

    public func translate(_ text: String, source: LanguageCode, target: LanguageCode) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: translationSystemPrompt(source: source, target: target)),
                    ChatMessage(role: "user", content: trimmed)
                ],
                temperature: 0.2
            )
        )

        let data = try await validatedData(for: request, session: session)
        return try Self.parseTranslationResponse(data)
    }

    public static func parseTranslationResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        let translated = cleanedTranslation(response.choices.first?.message.content ?? "")
        guard !translated.isEmpty else {
            throw TranslationError.missingTranslatedText
        }
        return translated
    }
}

public struct OllamaTranslator: TextTranslating {
    private let endpoint: URL
    private let model: String
    private let session: URLSession

    public init(
        endpoint: URL = OllamaConfiguration.defaultEndpoint,
        model: String = OllamaConfiguration.defaultModel,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint.normalizedOllamaChatEndpoint
        self.model = model
        self.session = session
    }

    public func translate(_ text: String, source: LanguageCode, target: LanguageCode) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            OllamaChatRequest(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: translationSystemPrompt(source: source, target: target)),
                    ChatMessage(role: "user", content: trimmed)
                ],
                stream: false,
                options: OllamaOptions(temperature: 0.2)
            )
        )

        let data = try await validatedData(for: request, session: session)
        return try Self.parseTranslationResponse(data)
    }

    public static func parseTranslationResponse(_ data: Data) throws -> String {
        let response = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let translated = cleanedTranslation(response.message.content)
        guard !translated.isEmpty else {
            throw TranslationError.missingTranslatedText
        }
        return translated
    }
}

private struct DeepLRequest: Encodable {
    let text: [String]
    let sourceLang: String
    let targetLang: String
    let context: String?

    private enum CodingKeys: String, CodingKey {
        case text
        case sourceLang = "source_lang"
        case targetLang = "target_lang"
        case context
    }
}

private struct DeepLResponse: Decodable {
    let translations: [Translation]

    struct Translation: Decodable {
        let text: String
    }
}

private struct PapagoResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let result: Result
    }

    struct Result: Decodable {
        let translatedText: String
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let temperature: Double
}

private struct OllamaChatResponse: Decodable {
    let message: ChatMessage
}

private func validatedData(for request: URLRequest, session: URLSession) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    if let httpResponse = response as? HTTPURLResponse,
       !(200...299).contains(httpResponse.statusCode) {
        throw TranslationError.httpStatus(httpResponse.statusCode)
    }
    return data
}

private func formBody(_ items: [(String, String)]) -> Data? {
    var components = URLComponents()
    components.queryItems = items.map(URLQueryItem.init)
    return components.percentEncodedQuery?.data(using: .utf8)
}

private func cleanedTranslation(_ text: String) -> String {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
        trimmed = trimmed
            .replacingOccurrences(of: #"^```[a-zA-Z]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if trimmed.count >= 2,
       trimmed.first == "\"",
       trimmed.last == "\"" {
        trimmed.removeFirst()
        trimmed.removeLast()
    }
    return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func translationSystemPrompt(source: LanguageCode, target: LanguageCode) -> String {
    """
    You translate manga dialogue from \(source.displayName) to \(target.displayName).
    Return only the translated Korean text, with no notes, quotes, markdown, censorship, or explanations.
    Preserve the speaker tone and line breaks when useful, but do not transliterate unless the source is a sound effect or name.
    """
}

private extension LanguageCode {
    var deepLCode: String {
        switch self {
        case .japanese:
            return "JA"
        case .korean:
            return "KO"
        case .english:
            return "EN"
        }
    }
}

private extension URL {
    var normalizedChatCompletionsEndpoint: URL {
        if path.hasSuffix("/chat/completions") {
            return self
        }
        return appendingPathComponent("chat", isDirectory: false)
            .appendingPathComponent("completions", isDirectory: false)
    }

    var normalizedOllamaChatEndpoint: URL {
        if path.hasSuffix("/api/chat") {
            return self
        }
        return appendingPathComponent("api", isDirectory: false)
            .appendingPathComponent("chat", isDirectory: false)
    }
}
