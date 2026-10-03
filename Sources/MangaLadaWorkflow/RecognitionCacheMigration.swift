import MangaLadaCore

/// Geometry refreshes keep region UUIDs and source boxes; fresh OCR creates new UUIDs.
/// Reviewed source/translation text belongs to those stable regions, not to the raw OCR cache.
package enum RecognitionCacheMigration {
    package static func reuse(_ stored: PageTranslation, for recognized: [TextBlock]) -> [TextBlock]? {
        guard stored.blocks.count == recognized.count,
              Set(stored.blocks.map(\.id)).count == stored.blocks.count,
              Set(recognized.map(\.id)).count == recognized.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: stored.blocks.map { ($0.id, $0) })
        guard recognized.allSatisfy({ block in
            guard let prior = byID[block.id] else { return false }
            return prior.box == block.box && !prior.translatedText.isEmpty
        }) else { return nil }
        return recognized.map { block in
            var updated = block
            updated.originalText = byID[block.id]!.originalText
            updated.translatedText = byID[block.id]!.translatedText
            updated.effectStyleID = byID[block.id]!.effectStyleID
            updated.textKind = byID[block.id]!.userDefinedTextKind == true ? byID[block.id]!.textKind : block.textKind ?? byID[block.id]!.textKind
            updated.userDefinedBounds = byID[block.id]!.userDefinedBounds
            updated.userDefinedTextKind = byID[block.id]!.userDefinedTextKind
            return updated
        }
    }
}
