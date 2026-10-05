import Foundation

/// Explicit OCR selection. Model failures never select another recognizer.
public enum JapaneseOCRBackend: String, Codable, CaseIterable, Sendable {
    case manga, hayai
    case hayaiDetected = "hayai-detected"
    case hayaiTextStrokes = "hayai-text-strokes"

    public var usesLetteringOCR: Bool { self != .manga }

    public var displayName: String {
        switch self {
        case .manga: "기본 만화 OCR"
        case .hayai: "장식 글자 OCR · Hayai"
        case .hayaiDetected: "장식 글자 OCR · 추가 검출 시험 적용"
        case .hayaiTextStrokes: "장식 글자 OCR · 정밀 획 분리 (+1.35GB)"
        }
    }
}

extension TextBlock {
    /// A review hold is independent of the user's explicit original-artwork choice.
    public var preservesOriginalArtwork: Bool { keepsOriginal == true || recognitionAlternatives != nil }
}
