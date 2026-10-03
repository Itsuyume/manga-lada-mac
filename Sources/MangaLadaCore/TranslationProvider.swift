import Foundation

public enum TranslationProvider: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case ollama
    case geminiFlashLite = "gemini_flash_lite"
    case googleWeb = "google_web"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: "로컬 · Ollama"
        case .geminiFlashLite: "저가 API · Gemini"
        case .googleWeb: "Google (기존 방식)"
        }
    }

    public var cacheKey: String {
        rawValue.replacingOccurrences(of: "_", with: "-")
    }
}
