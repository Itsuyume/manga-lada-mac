import Foundation

public enum TranslationProvider: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case ballonsGoogle = "ballons_google"
    case googleWeb = "google_web"
    case deepl = "deepl"
    case papago = "papago"
    case llm = "llm"
    case ollama = "ollama"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ballonsGoogle:
            return "Ballons Google"
        case .googleWeb:
            return "Google"
        case .deepl:
            return "DeepL"
        case .papago:
            return "Papago"
        case .llm:
            return "LLM"
        case .ollama:
            return "Ollama"
        }
    }

    public var cacheKey: String {
        rawValue.replacingOccurrences(of: "_", with: "-")
    }

    public var usesBallonsTranslator: Bool {
        self == .ballonsGoogle
    }
}
