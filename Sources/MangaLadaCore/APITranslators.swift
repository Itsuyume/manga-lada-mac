import Foundation

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
        let translated = cleanedOllamaTranslation(response.message.content)
        guard !translated.isEmpty else {
            throw TranslationError.missingTranslatedText
        }
        return translated
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

private struct ChatMessage: Codable {
    let role: String
    let content: String
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

private func cleanedOllamaTranslation(_ text: String) -> String {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("```"), trimmed.hasSuffix("```") {
        trimmed = trimmed
            .replacingOccurrences(of: #"^```[a-zA-Z]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    trimmed = trimmed
        .replacingOccurrences(
            of: #"(?i)^\s*(translation|translated text|korean translation|korean)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"^\s*(번역|한국어 번역|직역|의역)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"(単純|单纯)?\s*(文本|テキスト)?\s*翻(译|譯|訳)\s*[:：]\s*"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count >= 2,
       trimmed.first == "\"",
       trimmed.last == "\"" {
        trimmed.removeFirst()
        trimmed.removeLast()
    }

    guard containsHangul(trimmed) else {
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed
        .replacingOccurrences(
            of: #"[\p{Hiragana}\p{Katakana}\p{Han}]+"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"[A-Za-z]+"#,
            with: "",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"\s*[-–—]+\s*"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"\s+([,.!?…])"#,
            with: "$1",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func containsHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        (0xAC00...0xD7A3).contains(Int(scalar.value))
    }
}

private func translationSystemPrompt(source: LanguageCode, target: LanguageCode) -> String {
    """
    You translate manga dialogue from \(source.displayName) to \(target.displayName).
    Return only concise natural Korean text for the original speech bubble.
    Use Hangul and Korean punctuation only.
    Do not add labels, quotes, markdown, explanations, Chinese text, Japanese text, romaji, or the source text.
    Keep the line short enough to fit the original manga balloon.
    Preserve speaker tone, and transliterate names or sound effects into Korean when needed.
    """
}

private extension URL {
    var normalizedOllamaChatEndpoint: URL {
        if path.hasSuffix("/api/chat") {
            return self
        }
        return appendingPathComponent("api", isDirectory: false)
            .appendingPathComponent("chat", isDirectory: false)
    }
}
