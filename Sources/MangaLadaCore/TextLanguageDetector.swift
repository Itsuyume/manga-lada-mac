import Foundation

public enum TextLanguageDetector {
    public static func containsKorean(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3130...0x318F).contains($0.value) }
    }
    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }
    public static func detectSourceLanguage(
        in texts: [String],
        fallback: LanguageCode = .japanese
    ) -> LanguageCode {
        let scores = texts.reduce(LanguageScores()) { partial, text in
            partial.adding(text)
        }

        guard scores.hasText else {
            return fallback
        }

        if scores.japaneseKana >= 2 {
            return .japanese
        }

        if scores.latin >= max(4, scores.cjk * 2) {
            return .english
        }

        if scores.cjk > scores.latin {
            return .japanese
        }

        return fallback
    }
}

private struct LanguageScores {
    var latin = 0
    var japaneseKana = 0
    var cjk = 0

    var hasText: Bool {
        latin > 0 || japaneseKana > 0 || cjk > 0
    }

    func adding(_ text: String) -> LanguageScores {
        var copy = self
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0041...0x005A, 0x0061...0x007A:
                copy.latin += 1
            case 0x3040...0x309F, 0x30A0...0x30FF, 0xFF66...0xFF9D:
                copy.japaneseKana += 1
            case 0x4E00...0x9FFF:
                copy.cjk += 1
            default:
                continue
            }
        }
        return copy
    }
}
