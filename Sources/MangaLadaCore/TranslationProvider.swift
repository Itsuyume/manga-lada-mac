import Foundation

public enum TranslationProvider: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case ollama = "ollama"

    public var id: String { rawValue }

    public var displayName: String {
        "Ollama"
    }

    public var cacheKey: String {
        rawValue.replacingOccurrences(of: "_", with: "-")
    }
}
