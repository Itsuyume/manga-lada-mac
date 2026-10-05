import Foundation

extension TextBlock {
    /// Overlay only edited fields; keep new recognition/layout and unrelated automatic repairs.
    public func applyingReviewChanges(from baseline: Self, to edited: Self) -> Self {
        var result = self
        if baseline.originalText != edited.originalText { result.originalText = edited.originalText }
        if baseline.translatedText != edited.translatedText { result.translatedText = edited.translatedText }
        if baseline.recognitionAlternatives != edited.recognitionAlternatives { result.recognitionAlternatives = edited.recognitionAlternatives }
        if baseline.userDefinedOriginalText != edited.userDefinedOriginalText { result.userDefinedOriginalText = edited.userDefinedOriginalText }
        if baseline.keepsOriginal != edited.keepsOriginal { result.keepsOriginal = edited.keepsOriginal }
        if baseline.textKind != edited.textKind
            || (edited.userDefinedTextKind == true && baseline.userDefinedTextKind != true) {
            result.textKind = edited.textKind
        }
        if baseline.userDefinedTextKind != edited.userDefinedTextKind { result.userDefinedTextKind = edited.userDefinedTextKind }
        if baseline.maskedTextInterpretation != edited.maskedTextInterpretation { result.maskedTextInterpretation = edited.maskedTextInterpretation }
        return result.applyingLetteringChanges(from: baseline, to: edited)
    }

    private func applyingLetteringChanges(from baseline: Self, to edited: Self) -> Self {
        var result = self
        if baseline.effectStyleID != edited.effectStyleID { result.effectStyleID = edited.effectStyleID }
        if baseline.textDirection != edited.textDirection { result.textDirection = edited.textDirection }
        if baseline.fontScale != edited.fontScale { result.fontScale = edited.fontScale }
        if baseline.textOffset != edited.textOffset { result.textOffset = edited.textOffset }
        if baseline.textLayoutBounds != edited.textLayoutBounds { result.textLayoutBounds = edited.textLayoutBounds }
        return result
    }
}
