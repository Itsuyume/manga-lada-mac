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
