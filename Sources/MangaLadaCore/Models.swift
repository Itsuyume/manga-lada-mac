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
    public var originalText: String {
        didSet {
            if originalText != oldValue { maskedTextInterpretation = nil; recognitionAlternatives = nil }
        }
    }
    public var translatedText: String
    /// Explicit user choice: restore source artwork and exclude this region from translation.
    /// Nil in older caches means normal translation. Previous text is retained for undo.
    public var keepsOriginal: Bool?
    /// Non-nil means OCR disagreed. Keep artwork until the source is corrected/confirmed.
    /// An empty array is a detected region with no readable candidate, not a confirmed blank.
    public var recognitionAlternatives: [String]?
    public var confidence: Float
    public var sourceIsVertical: Bool?
    public var detectedFontSize: Double?
    public var textKind: MangaTextKind?
    public var rotationDegrees: Double?
    public var balloonShape: BalloonShape?
    public var effectStyleID: String?
    public var textDirection: TextDirection?
    public var fontScale: Double?
    /// Manual displacement in normalized page coordinates, positive y downward.
    public var textOffset: TextOffset?
    /// Typesetting space only; never changes recognition or source erasure.
    public var textLayoutBounds: TextBox?
    public var userDefinedBounds: TextBox?
    public var userDefinedTextKind: Bool?
    /// True: applied source edit. False: source matches OCR. Nil: provenance is unverified.
    public var userDefinedOriginalText: Bool?
    /// Exact source region read by manual OCR for unchanged punctuation; absent in legacy caches.
    public var verifiedPunctuationBounds: TextBox?
    public var maskedTextInterpretation: MaskedTextInterpretation?

    public init(
        id: UUID = UUID(),
        box: TextBox,
        originalText: String,
        translatedText: String = "",
        keepsOriginal: Bool? = nil,
        recognitionAlternatives: [String]? = nil,
        confidence: Float = 0,
        sourceIsVertical: Bool? = nil,
        detectedFontSize: Double? = nil,
        textKind: MangaTextKind? = nil,
        rotationDegrees: Double? = nil,
        balloonShape: BalloonShape? = nil,
        effectStyleID: String? = nil,
        textDirection: TextDirection? = nil,
        fontScale: Double? = nil,
        textOffset: TextOffset? = nil,
        textLayoutBounds: TextBox? = nil,
        userDefinedBounds: TextBox? = nil,
        userDefinedTextKind: Bool? = nil,
        userDefinedOriginalText: Bool? = nil,
        verifiedPunctuationBounds: TextBox? = nil,
        maskedTextInterpretation: MaskedTextInterpretation? = nil
    ) {
        self.id = id
        self.box = box
        self.originalText = originalText
        self.translatedText = translatedText
        self.keepsOriginal = keepsOriginal
        self.recognitionAlternatives = recognitionAlternatives
        self.confidence = confidence
        self.sourceIsVertical = sourceIsVertical
        self.detectedFontSize = detectedFontSize
        self.textKind = textKind
        self.rotationDegrees = rotationDegrees
        self.balloonShape = balloonShape
        self.effectStyleID = effectStyleID
        self.textDirection = textDirection
        self.fontScale = fontScale
        self.textOffset = textOffset
        self.textLayoutBounds = textLayoutBounds
        self.userDefinedBounds = userDefinedBounds
        self.userDefinedTextKind = userDefinedTextKind
        self.userDefinedOriginalText = userDefinedOriginalText
        self.verifiedPunctuationBounds = verifiedPunctuationBounds
        self.maskedTextInterpretation = maskedTextInterpretation
    }
}

public struct PageTranslation: Codable, Equatable, Sendable {
    public var imageURL: URL
    public var imageFingerprint: String
    public var sourceLanguage: LanguageCode
    public var targetLanguage: LanguageCode
    public var createdAt: Date
    public var blocks: [TextBlock]
    public var untranslatedBlockIDs: Set<UUID> {
        Set(blocks.filter { !$0.preservesOriginalArtwork && $0.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.id))
    }
    public var maskedTextReviewIDs: Set<UUID> {
        Set(blocks.filter { !$0.preservesOriginalArtwork && MaskedTextTranslation.reviewMessage(for: $0) != nil }.map(\.id))
    }

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

    public static let comicSourceLanguages: [Self] = [.japanese, .english]
    public func validateComicSource() throws {
        guard Self.comicSourceLanguages.contains(self) else {
            throw TranslationError.missingConfiguration("원문 언어는 일본어 또는 영어를 선택해주세요.")
        }
    }
    public var localizedName: String {
        switch self {
        case .japanese: "일본어"
        case .english: "영어"
        case .korean: "한국어"
        }
    }

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
