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
    /// Fresh OCR creates a new ID. Geometry refreshes retain it, even when a user edits the source text.
    public var id: UUID
    public var box: TextBox
    public var originalText: String
    public var translatedText: String
    public var confidence: Float
    public var sourceIsVertical: Bool?
    public var detectedFontSize: Double?
    public var textKind: MangaTextKind?
    public var rotationDegrees: Double?
    public var balloonShape: BalloonShape?
    public var effectStyleID: String?
    public var userDefinedBounds: TextBox?
    public var userDefinedTextKind: Bool?
    public var userDefinedOriginalText: Bool?

    public init(
        id: UUID = UUID(),
        box: TextBox,
        originalText: String,
        translatedText: String = "",
        confidence: Float = 0,
        sourceIsVertical: Bool? = nil,
        detectedFontSize: Double? = nil,
        textKind: MangaTextKind? = nil,
        rotationDegrees: Double? = nil,
        balloonShape: BalloonShape? = nil,
        effectStyleID: String? = nil,
        userDefinedBounds: TextBox? = nil,
        userDefinedTextKind: Bool? = nil,
        userDefinedOriginalText: Bool? = nil
    ) {
        self.id = id
        self.box = box
        self.originalText = originalText
        self.translatedText = translatedText
        self.confidence = confidence
        self.sourceIsVertical = sourceIsVertical
        self.detectedFontSize = detectedFontSize
        self.textKind = textKind
        self.rotationDegrees = rotationDegrees
        self.balloonShape = balloonShape
        self.effectStyleID = effectStyleID
        self.userDefinedBounds = userDefinedBounds
        self.userDefinedTextKind = userDefinedTextKind
        self.userDefinedOriginalText = userDefinedOriginalText
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

    public var visionRecognitionLanguages: [String] {
        switch self {
        case .japanese:
            return ["ja-JP", "en-US"]
        case .korean:
            return ["ko-KR", "en-US"]
        case .english:
            return ["en-US"]
        }
    }

    public static let automaticVisionRecognitionLanguages = ["ja-JP", "en-US"]
}

public enum AppMode: String, Codable, Equatable, Sendable {
    case imageOnly
    case translated
}
