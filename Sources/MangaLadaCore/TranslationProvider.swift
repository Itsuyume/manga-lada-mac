import Foundation

public enum TranslationProvider: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case googleWeb = "google_web"

    public var id: String { rawValue }

    public var displayName: String {
        "Google"
    }

    public var cacheKey: String {
        rawValue.replacingOccurrences(of: "_", with: "-")
    }
}
