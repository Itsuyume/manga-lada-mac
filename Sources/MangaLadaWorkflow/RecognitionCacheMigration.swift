import MangaLadaCore

/// Geometry refreshes keep region UUIDs and source boxes; fresh OCR creates new UUIDs.
/// Reviewed source/translation text belongs to those stable regions, not to the raw OCR cache.
package enum RecognitionCacheMigration {
    package static func reuse(_ stored: PageTranslation, for recognized: [TextBlock]) -> [TextBlock]? {
        guard stored.blocks.count <= recognized.count,
              Set(stored.blocks.map(\.id)).count == stored.blocks.count,
              Set(recognized.map(\.id)).count == recognized.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: stored.blocks.map { ($0.id, $0) })
        let recognizedByID = Dictionary(uniqueKeysWithValues: recognized.map { ($0.id, $0) })
        guard stored.blocks.allSatisfy({ prior in
            guard let block = recognizedByID[prior.id] else { return false }
            return prior.box == block.box && !prior.translatedText.isEmpty
        }) else { return nil }
        return recognized.map { block in
            guard let prior = byID[block.id] else { return block }
            var updated = block
            updated.originalText = prior.originalText
            updated.translatedText = prior.translatedText
            updated.effectStyleID = prior.effectStyleID
            updated.textKind = prior.userDefinedTextKind == true ? prior.textKind : block.textKind ?? prior.textKind
            updated.userDefinedBounds = prior.userDefinedBounds
            updated.userDefinedTextKind = prior.userDefinedTextKind
            return updated
        }
    }
}
