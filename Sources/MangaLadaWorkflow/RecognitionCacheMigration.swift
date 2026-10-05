import MangaLadaCore

/// Geometry refreshes keep region UUIDs and source boxes; fresh OCR creates new UUIDs.
/// Reviewed source/translation text belongs to those stable regions, not to the raw OCR cache.
package enum RecognitionCacheMigration {
    package static func recordSourceEdits(in blocks: [TextBlock], recognized: [TextBlock]) -> [TextBlock] {
        let byID = Dictionary(grouping: recognized, by: \.id)
        return blocks.map { block in
            guard block.userDefinedOriginalText == nil, let matches = byID[block.id], matches.count == 1,
                  let old = matches.first, old.box == block.box else { return block }
            var updated = block
            updated.userDefinedOriginalText = old.originalText != block.originalText
            return updated
        }
    }
    package static func hasUnverifiedPunctuation(in blocks: [TextBlock]) -> Bool {
        blocks.contains { needsPunctuationVerification($0) }
    }

    /// A legacy source may have been edited before provenance was recorded.
    /// Missing, moved or ambiguous OCR cannot authorize restoring source artwork.
    package static func verifyPunctuation(in blocks: [TextBlock], recognized: [TextBlock]?) -> [TextBlock] {
        guard let recognized else { return blocks }
        let byID = Dictionary(grouping: recognized, by: \.id)
        return blocks.map { block in
            guard needsPunctuationVerification(block), let matches = byID[block.id], matches.count == 1,
                  let source = matches.first, source.box == block.box else { return block }
            var updated = block
            updated.userDefinedOriginalText = source.originalText != block.originalText
            return updated
        }
    }

    private static func needsPunctuationVerification(_ block: TextBlock) -> Bool {
        block.userDefinedOriginalText == nil && PunctuationArtworkPolicy.isCandidate(block)
    }

    package static func reuse(_ stored: PageTranslation, for recognized: [TextBlock], preservingOriginalOnly: Bool = false,
                              requiresMatchingSource: Bool = false) -> [TextBlock]? {
        guard Set(stored.blocks.map(\.id)).count == stored.blocks.count,
              Set(recognized.map(\.id)).count == recognized.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: stored.blocks.map { ($0.id, $0) })
        let unchanged = recognized.filter { block in
            guard let prior = byID[block.id] else { return false }
            if prior.keepsOriginal != true && prior.userDefinedOriginalText != true {
                guard block.recognitionAlternatives == nil,
                      !requiresMatchingSource || prior.originalText == block.originalText else { return false }
            }
            return prior.box == block.box && (prior.keepsOriginal == true || (!preservingOriginalOnly && !prior.translatedText.isEmpty))
        }
        let hasLayout = requiresMatchingSource && recognized.contains { block in byID[block.id]?.box == block.box }
        guard !unchanged.isEmpty || hasLayout else { return nil }
        let reusableIDs = Set(unchanged.map(\.id))
        return recognized.map { block in
            guard let prior = byID[block.id], prior.box == block.box,
                  reusableIDs.contains(block.id) || requiresMatchingSource else { return block }
            var updated = block
            if reusableIDs.contains(block.id) {
                updated.originalText = prior.originalText
                updated.translatedText = prior.translatedText
                updated.keepsOriginal = prior.keepsOriginal
                updated.recognitionAlternatives = prior.recognitionAlternatives
                updated.userDefinedOriginalText = prior.userDefinedOriginalText ?? (prior.originalText != block.originalText ? true : nil)
                updated.verifiedPunctuationBounds = prior.verifiedPunctuationBounds
                updated.maskedTextInterpretation = prior.maskedTextInterpretation
            } else if requiresMatchingSource && prior.userDefinedOriginalText == true {
                updated.originalText = prior.originalText
                updated.recognitionAlternatives = prior.recognitionAlternatives
                updated.userDefinedOriginalText = true
            }
            updated.effectStyleID = prior.effectStyleID
            updated.textDirection = prior.textDirection
            updated.fontScale = prior.fontScale
            updated.textOffset = prior.textOffset
            updated.textLayoutBounds = prior.textLayoutBounds
            updated.textKind = prior.userDefinedTextKind == true ? prior.textKind : block.textKind ?? prior.textKind
            updated.userDefinedBounds = prior.userDefinedBounds
            updated.userDefinedTextKind = prior.userDefinedTextKind
            return updated
        }
    }
}
