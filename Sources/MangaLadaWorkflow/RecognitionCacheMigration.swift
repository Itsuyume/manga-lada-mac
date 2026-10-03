import MangaLadaCore

/// A geometry revision may reuse language only when every source region still matches exactly.
enum RecognitionCacheMigration {
    static func reuse(_ stored: PageTranslation, for recognized: [TextBlock]) -> [TextBlock]? {
        guard stored.blocks.count == recognized.count,
              Set(stored.blocks.map(\.id)).count == stored.blocks.count,
              Set(recognized.map(\.id)).count == recognized.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: stored.blocks.map { ($0.id, $0) })
        guard recognized.allSatisfy({ block in
            guard let prior = byID[block.id] else { return false }
            return prior.originalText == block.originalText && !prior.translatedText.isEmpty
        }) else { return nil }
        return recognized.map { block in
            var updated = block
            updated.translatedText = byID[block.id]!.translatedText
            updated.effectStyleID = byID[block.id]!.effectStyleID
            updated.textKind = byID[block.id]!.userDefinedTextKind == true ? byID[block.id]!.textKind : block.textKind ?? byID[block.id]!.textKind
            updated.userDefinedBounds = byID[block.id]!.userDefinedBounds
            updated.userDefinedTextKind = byID[block.id]!.userDefinedTextKind
            return updated
        }
    }
}
