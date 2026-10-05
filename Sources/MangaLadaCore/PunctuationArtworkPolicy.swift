import Foundation

/// Shared metadata eligibility; source provenance and pixel geometry are checked separately.
public enum PunctuationArtworkPolicy {
    public static func isCandidate(_ block: TextBlock) -> Bool {
        sourceBounds(for: block) != nil
    }

    public static func sourceBounds(for block: TextBlock) -> TextBox? {
        let source = block.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TextLanguageDetector.isPunctuationOnly(source),
              source == block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines),
              block.effectStyleID == nil, block.textDirection == nil, block.fontScale == nil, block.textOffset == nil, block.textLayoutBounds == nil,
              block.userDefinedOriginalText != true else { return nil }
        if let verified = block.verifiedPunctuationBounds {
            guard block.userDefinedOriginalText == false, let selection = block.userDefinedBounds,
                  ImageRegionSelection.validates(verified), ImageRegionSelection.validates(selection),
                  verified.intersectionArea(with: selection) >= verified.area * (1 - 1e-9) else { return nil }
            return verified
        }
        guard block.userDefinedBounds == nil, block.userDefinedTextKind != true,
              ImageRegionSelection.validates(block.box) else { return nil }
        return block.box
    }
}
