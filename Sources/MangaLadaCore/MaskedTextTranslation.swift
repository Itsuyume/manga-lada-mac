import Foundation

/// Resolve catalogued names in context; preserve omissions that remain uncertain.
public enum MaskedTextTranslation {
    private static let circleCharacters = "○◯〇"
    private static let circles = Set(circleCharacters)
    private static let numerals = Set("0123456789０１２３４５６７８９零一二三四五六七八九十百千万億兆")
    private static let numberUnits = Set("年月日時分秒点円個人本回階歳才度頁")

    /// Word-internal masks only: anonymous names, numeric zero and standalone Latin O are not guesses.
    public static func requiresContextTranslation(_ source: String) -> Bool {
        let normalized = normalizedSpelling(source)
        let pattern = #"[\p{Hiragana}\p{Katakana}\p{Han}ー][○◯〇]+[\p{Hiragana}\p{Katakana}\p{Han}ー]"#
        return hasUnresolvedCircles(normalized) && normalized.range(of: pattern, options: .regularExpression) != nil
    }

    public static func reviewMessage(for block: TextBlock) -> String? {
        guard requiresContextTranslation(block.originalText), !block.translatedText.isEmpty else { return nil }
        do { try validateKnownNames(block.translatedText, source: block.originalText) }
        catch { return "가린 이름과 번역이 맞지 않습니다. Qwen으로 이 문구를 다시 확인하세요." }
        if block.maskedTextInterpretation?.translationModel == OllamaConfiguration.visionModel {
            return block.maskedTextInterpretation?.japanese == nil
                ? "가린 단어의 뜻이 아직 확인되지 않았습니다. 원문·문맥을 확인하거나 다시 번역하세요." : nil
        }
        return "이전 번역 결과입니다. Qwen으로 이 문구만 다시 확인할 수 있습니다."
    }

    static func instruction(for texts: [String]) -> String {
        let prepared = texts.map(resolution)
        let terms = Array(Set(prepared.flatMap { $0.terms.map { "\($0.key) -> \($0.value)" } })).sorted()
        var rules: [String] = []
        if !terms.isEmpty { rules.append("Use these Korean name translations: " + terms.joined(separator: "; ") + ".") }
        if prepared.contains(where: { !sourceLengths(in: $0.text).isEmpty }) {
            rules.append("""
            The source contains intentional masked spelling (伏字). Preserve every remaining ○, ◯ or 〇 placeholder as ○, keeping each run's exact count. Translate or transliterate only the visible parts of unresolved names into Korean. Do not guess the complete name or substitute another title. Do not replace a mask with hesitation, ellipses, 'blah blah', an explanation or a missing syllable. Examples: ○○さん -> ○○ 씨; 山○ -> 야마○. A numeric 〇 in a date/number means zero: 二〇二六年 -> 2026년. Other Latin O letters remain letters.
            """)
        }
        return rules.joined(separator: "\n")
    }

    static func modelText(_ source: String) -> String { resolution(source).text }
    /// An O between kana of the same script is a mask candidate; Oリング and O型 remain letters.
    static func normalizedSpelling(_ source: String) -> String {
        let pattern = #"(?:(?<=[\p{Hiragana}])[OＯ]+(?=[\p{Hiragana}])|(?<=[\p{Katakana}ー])[OＯ]+(?=[\p{Katakana}ー]))(?!リング)"#
        var matches: [Range<String.Index>] = []
        var remaining = source.startIndex..<source.endIndex
        while let range = source.range(of: pattern, options: .regularExpression, range: remaining) {
            matches.append(range); remaining = range.upperBound..<source.endIndex
        }
        var result = source
        for range in matches.reversed() {
            result.replaceSubrange(range, with: String(repeating: "○", count: source[range].count))
        }
        return result
    }
    static func hasUnresolvedCircles(_ source: String) -> Bool { !sourceLengths(in: source).isEmpty }

    static func validateKnownNames(_ translated: String, source: String) throws {
        for name in resolution(source).koreanNames where !translated.contains(name) {
            throw TranslationError.invalidPageResponse("문맥으로 확인한 고유명사의 번역이 빠지거나 바뀌었습니다. 한국어 명칭 '\(name)'을 사용해야 합니다.")
        }
    }

    static func validated(_ translated: String, source: String) throws -> String {
        let resolved = resolution(source)
        guard !resolved.koreanNames.isEmpty || !sourceLengths(in: resolved.text).isEmpty else { return translated }
        try validateKnownNames(translated, source: source)
        let expected = sourceLengths(in: resolved.text).sorted()
        let compact = compactedCircles(translated)
        let actual = groups(in: compact).map { compact[$0].count }.sorted()
        guard actual == expected else {
            throw TranslationError.invalidPageResponse("원문의 가림표(○)가 번역에서 사라지거나 개수가 바뀌었습니다. 가린 이름을 추측하지 말고 가림표를 그대로 유지해야 합니다.")
        }
        return compact.map { circles.contains($0) ? "○" : String($0) }.joined()
    }

    private static func resolution(_ source: String) -> JapaneseMaskedNameLexicon.Resolution {
        JapaneseMaskedNameLexicon.resolve(normalizedSpelling(source), maskCharacters: circleCharacters + "OＯ")
    }

    private static func sourceLengths(in text: String) -> [Int] {
        let text = compactedCircles(text)
        return groups(in: text).filter { range in
            let marks = text[range]
            guard marks.allSatisfy({ $0 == "〇" }) else { return true }
            let before = range.lowerBound > text.startIndex ? text[text.index(before: range.lowerBound)] : nil
            let after = range.upperBound < text.endIndex ? text[range.upperBound] : nil
            let neighbors = [before, after].compactMap { $0 }
            guard !neighbors.contains(where: { numerals.contains($0) }) else { return false }
            guard !text[range.upperBound...].hasPrefix("ページ") else { return false }
            if marks.count > 1 { return true }
            return neighbors.contains { !numberUnits.contains($0) && TextLanguageDetector.containsJapanese(String($0)) }
        }.map { text[$0].count }
    }

    private static func compactedCircles(_ text: String) -> String {
        let pattern = "(?<=[\(circleCharacters)])\\s+(?=[\(circleCharacters)])"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func groups(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            if circles.contains(text[index]) {
                if start == nil { start = index }
            } else if let lower = start {
                ranges.append(lower..<index)
                start = nil
            }
        }
        if let start { ranges.append(start..<text.endIndex) }
        return ranges
    }
}
