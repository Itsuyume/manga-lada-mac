import Foundation

extension TextBlock {
    /// Overlay only edited fields; keep new recognition/layout and unrelated automatic repairs.
    public func applyingReviewChanges(from baseline: Self, to edited: Self) -> Self {
        var result = self
        if baseline.originalText != edited.originalText { result.originalText = edited.originalText }
        if baseline.translatedText != edited.translatedText { result.translatedText = edited.translatedText }
        if baseline.textKind != edited.textKind
            || (edited.userDefinedTextKind == true && baseline.userDefinedTextKind != true) {
            result.textKind = edited.textKind
        }
        if baseline.userDefinedTextKind != edited.userDefinedTextKind { result.userDefinedTextKind = edited.userDefinedTextKind }
        if baseline.effectStyleID != edited.effectStyleID { result.effectStyleID = edited.effectStyleID }
        if baseline.maskedTextInterpretation != edited.maskedTextInterpretation { result.maskedTextInterpretation = edited.maskedTextInterpretation }
        return result
    }
}
