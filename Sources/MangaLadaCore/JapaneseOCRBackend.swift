import Foundation

/// Explicit OCR selection. Model failures never select another recognizer.
public enum JapaneseOCRBackend: String, Codable, CaseIterable, Sendable {
    case manga, hayai

    public var displayName: String {
        switch self {
        case .manga: "기본 만화 OCR"
        case .hayai: "장식 글자 OCR · Hayai"
        }
    }
}

extension TextBlock {
    /// A review hold is independent of the user's explicit original-artwork choice.
    public var preservesOriginalArtwork: Bool { keepsOriginal == true || recognitionAlternatives != nil }
}
