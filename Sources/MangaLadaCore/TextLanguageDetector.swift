import Foundation

public enum TextLanguageDetector {
    private static let punctuation = CharacterSet(charactersIn: ".…‥⋯・·!?,。、？！‼⁇⁈⁉—–―ー〜~")
    private static let wrappers = CharacterSet(charactersIn: "\"'“”‘’「」『』()[]【】〈〉《》").union(.whitespacesAndNewlines)

    public static func containsKorean(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3130...0x318F).contains($0.value) }
    }
    public static func containsEnglish(_ text: String) -> Bool {
        text.range(of: #"\p{Latin}"#, options: .regularExpression) != nil
    }
    public static func containsSourceText(_ text: String, language: LanguageCode) -> Bool {
        switch language {
        case .japanese: containsJapanese(text)
        case .english: containsEnglish(text)
        case .korean: containsKorean(text)
        }
    }
    public static func containsJapanese(_ text: String) -> Bool {
        // ICU script extensions also include shared marks such as U+301C.
        // Remove known punctuation before checking letters; NFKC covers halfwidth kana.
        let letters = text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            !punctuation.contains($0) && !wrappers.contains($0) && $0.properties.generalCategory != .letterNumber
        }
        return String(String.UnicodeScalarView(letters))
            .range(of: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#, options: .regularExpression) != nil
    }
    /// Speech pauses, surprise marks and standalone sokuon may translate to punctuation.
    /// Words, digits, empty quotes and commentary cannot use this exception.
    static func isNonverbalTranslation(_ text: String, source: String) -> Bool {
        let sourceMarks = punctuation.union(CharacterSet(charactersIn: "っッ"))
        return containsOnlyMarks(source, marks: sourceMarks) && isPunctuationOnly(text)
    }

    /// Pure symbols have no language to translate. Standalone kana still require translation.
    public static func isPunctuationOnly(_ text: String) -> Bool {
        containsOnlyMarks(text, marks: punctuation)
    }

    private static func containsOnlyMarks(_ text: String, marks: CharacterSet) -> Bool {
        let scalars = text.precomposedStringWithCompatibilityMapping.unicodeScalars
        let allowed = marks.union(wrappers)
        return scalars.contains { marks.contains($0) } && scalars.allSatisfy { allowed.contains($0) }
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
