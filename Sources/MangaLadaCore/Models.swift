import Foundation

public struct TextBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct TextBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var box: TextBox
    public var originalText: String
    public var translatedText: String
    public var confidence: Float

    public init(
        id: UUID = UUID(),
        box: TextBox,
        originalText: String,
        translatedText: String = "",
        confidence: Float = 0
    ) {
        self.id = id
        self.box = box
        self.originalText = originalText
        self.translatedText = translatedText
        self.confidence = confidence
    }
}

public struct PageTranslation: Codable, Equatable, Sendable {
    public var imageURL: URL
    public var imageFingerprint: String
    public var sourceLanguage: LanguageCode
    public var targetLanguage: LanguageCode
    public var createdAt: Date
    public var blocks: [TextBlock]

    public init(
        imageURL: URL,
        imageFingerprint: String,
        sourceLanguage: LanguageCode,
        targetLanguage: LanguageCode,
        createdAt: Date = Date(),
        blocks: [TextBlock]
    ) {
        self.imageURL = imageURL
        self.imageFingerprint = imageFingerprint
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
        self.blocks = blocks
    }
}

public struct ImagePage: Identifiable, Equatable, Sendable {
    public var id: URL { url }
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public enum LanguageCode: String, Codable, CaseIterable, Equatable, Sendable {
    case japanese = "ja"
    case korean = "ko"
    case english = "en"

    public var displayName: String {
        switch self {
        case .japanese:
            return "Japanese"
        case .korean:
            return "Korean"
        case .english:
            return "English"
        }
    }
}

public enum AppMode: String, Codable, Equatable, Sendable {
    case imageOnly
    case translated
}
