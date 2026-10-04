import Foundation

/// Shared metadata eligibility; source provenance and pixel geometry are checked separately.
public enum PunctuationArtworkPolicy {
    public static func isCandidate(_ block: TextBlock) -> Bool {
        let source = block.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return TextLanguageDetector.isPunctuationOnly(source)
            && source == block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            && block.userDefinedBounds == nil && block.userDefinedTextKind != true
            && block.effectStyleID == nil && block.userDefinedOriginalText != true
            && ImageRegionSelection.validates(block.box)
    }
}
