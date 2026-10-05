import MangaLadaCore

/// Geometry refreshes keep region UUIDs and source boxes; fresh OCR creates new UUIDs.
/// Reviewed source/translation text belongs to those stable regions, not to the raw OCR cache.
package enum RecognitionCacheMigration {
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

    package static func reuse(_ stored: PageTranslation, for recognized: [TextBlock]) -> [TextBlock]? {
        guard Set(stored.blocks.map(\.id)).count == stored.blocks.count,
              Set(recognized.map(\.id)).count == recognized.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: stored.blocks.map { ($0.id, $0) })
        let unchanged = recognized.filter { block in
            guard let prior = byID[block.id] else { return false }
            return prior.box == block.box && !prior.translatedText.isEmpty
        }
        guard !unchanged.isEmpty else { return nil }
        let reusableIDs = Set(unchanged.map(\.id))
        return recognized.map { block in
            guard reusableIDs.contains(block.id), let prior = byID[block.id] else { return block }
            var updated = block
            updated.originalText = prior.originalText
            updated.translatedText = prior.translatedText
            updated.effectStyleID = prior.effectStyleID
            updated.textDirection = prior.textDirection
            updated.fontScale = prior.fontScale
            updated.textOffset = prior.textOffset
            updated.textLayoutBounds = prior.textLayoutBounds
            updated.textKind = prior.userDefinedTextKind == true ? prior.textKind : block.textKind ?? prior.textKind
            updated.userDefinedBounds = prior.userDefinedBounds
            updated.userDefinedTextKind = prior.userDefinedTextKind
            updated.userDefinedOriginalText = prior.userDefinedOriginalText ?? (prior.originalText != block.originalText ? true : nil)
            updated.verifiedPunctuationBounds = prior.verifiedPunctuationBounds
            updated.maskedTextInterpretation = prior.maskedTextInterpretation
            return updated
        }
    }
}
