import Foundation

public enum TranslationError: LocalizedError, Equatable {
    case emptyText
    case invalidResponse
    case httpStatus(Int)
    case missingTranslatedText
    case missingConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            return "번역할 텍스트가 비어 있습니다."
        case .invalidResponse:
            return "번역 서버 응답을 해석할 수 없습니다."
        case .httpStatus(let status):
            return "번역 서버가 HTTP \(status)를 반환했습니다."
        case .missingTranslatedText:
            return "번역 결과 텍스트가 없습니다."
        case .missingConfiguration(let message):
            return message
        }
    }
}

public protocol TextTranslating: Sendable {
    func translate(
        _ text: String,
        source: LanguageCode,
        target: LanguageCode
    ) async throws -> String
}

public protocol BatchTextTranslating: TextTranslating {
    func translate(
        _ texts: [String],
        source: LanguageCode,
        target: LanguageCode
    ) async throws -> [String]
}

public extension BatchTextTranslating {
    func translate(
        _ text: String,
        source: LanguageCode,
        target: LanguageCode
    ) async throws -> String {
        let translated = try await translate([text], source: source, target: target)
        guard let first = translated.first else {
            throw TranslationError.missingTranslatedText
        }
        return first
    }
}

public struct PassthroughTranslator: TextTranslating {
    public init() {}

    public func translate(
        _ text: String,
        source: LanguageCode,
        target: LanguageCode
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }
        return trimmed
    }
}

public struct GoogleWebTranslator: TextTranslating {
    private let endpoint: URL
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "https://translate.googleapis.com/translate_a/single")!,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.session = session
    }

    public func translate(
        _ text: String,
        source: LanguageCode,
        target: LanguageCode
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.emptyText
        }

        let url = try requestURL(text: trimmed, source: source, target: target)
        let (data, response) = try await session.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw TranslationError.httpStatus(httpResponse.statusCode)
        }

        return try Self.parseTranslationResponse(data)
    }

    public func requestURL(
        text: String,
        source: LanguageCode,
        target: LanguageCode
    ) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TranslationError.invalidResponse
        }

        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source.rawValue),
            URLQueryItem(name: "tl", value: target.rawValue),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]

        guard let url = components.url else {
            throw TranslationError.invalidResponse
        }
        return url
    }

    public static func parseTranslationResponse(_ data: Data) throws -> String {
        let payload = try JSONSerialization.jsonObject(with: data)
        guard let root = payload as? [Any],
              let sentenceGroups = root.first as? [Any] else {
            throw TranslationError.invalidResponse
        }

        let translated = sentenceGroups.compactMap { group -> String? in
            guard let parts = group as? [Any], let text = parts.first as? String else {
                return nil
            }
            return text
        }.joined()

        let trimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TranslationError.missingTranslatedText
        }
        return trimmed
    }
}
