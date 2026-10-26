import Foundation

/// Narrow source/translation contradictions, not a semantic-accuracy score or global replacement.
public enum JapaneseTermDisambiguation {
    static let femaleOrganTerms = ["まんこ", "マンコ", "おまんこ"]
    private static let maleOrganTerms = ["陰茎", "ペニス", "ちんぽ", "チンポ", "ちんちん", "チンチン"]
    private static let anatomicalContext = ["女性器", "男性器", "性器", "陰部", "陰茎", "ペニス", "膣", "精子", "射精"]
    private static let otherMeanings = ["毛", "いんもう", "陰謀", "いんぼう", "企み", "たくらみ"]

    static func instruction(for sources: [String]) -> String {
        guard sources.contains(where: { targetsOrganMeaning($0) || $0.contains("陰毛") }) else { return "" }
        return "Anatomical terminology: a genital organ, pubic hair (陰毛, 음모), and hair on the head (頭髪, 머리카락) are different. Preserve the source meaning and register; never replace a body part with a different part or add hair where the source only names an organ."
    }

    static func validate(_ translation: String, source: String) throws {
        if let message = issue(translation, source: source) { throw TranslationError.invalidPageResponse(message) }
    }

    public static func reviewMessage(for block: TextBlock) -> String? {
        guard !block.preservesOriginalArtwork, !block.translatedText.isEmpty else { return nil }
        return issue(block.translatedText, source: block.originalText)
    }

    private static func issue(_ translation: String, source: String) -> String? {
        let normalized = source.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        if normalized.contains("陰毛"), !normalized.contains("髪"), !normalized.contains("頭の毛"), translation.contains("머리카락") {
            return "원문의 체모를 머리카락으로 바꾸었습니다. 陰毛는 음모(체모)이며 머리카락이 아닙니다. 원문 부위를 구별하여 번역해주세요."
        }
        if targetsOrganMeaning(normalized), !otherMeanings.contains(where: normalized.contains), translation.contains("음모") {
            return "원문의 신체 부위를 체모인 ‘음모’로 바꾸었습니다. 신체 부위와 체모를 구별하여 원문 뜻을 번역해주세요."
        }
        return nil
    }

    private static func targetsOrganMeaning(_ source: String) -> Bool {
        let normalized = source.precomposedStringWithCompatibilityMapping.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let female = femaleOrganTerms.contains(where: normalized.contains)
        let male = maleOrganTerms.contains(where: normalized.contains)
        // A proper name or a homonym such as a dog trick/streetcar is not enough evidence.
        return (female || male) && ((female && male) || anatomicalContext.contains(where: normalized.contains))
    }
}
