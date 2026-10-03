import Foundation

/// Reconciles OCR coordinates with semantic sound-effect detection at one boundary.
public enum JapaneseRegionMerger {
    /// A balloon is one typesetting unit. Remove contained OCR duplicates before joining split regions.
    public static func speechRegions(_ blocks: [TextBlock]) -> [TextBlock] {
        let unique = blocks.enumerated().filter { index, block in
            !blocks.enumerated().contains { otherIndex, other in
                guard index != otherIndex, normalized(other.originalText).contains(normalized(block.originalText)),
                      block.box.intersectionArea(with: other.box) / max(0.000001, block.box.area) > 0.8 else { return false }
                return other.box.area > block.box.area * 1.25 || (other.originalText == block.originalText && otherIndex < index)
            }
        }.map(\.element)
        var resolved: [TextBlock] = []
        for block in MangaReadingOrder.sorted(unique) {
            guard let shape = block.balloonShape, block.textKind != .title, block.textKind != .soundEffect,
                  let index = resolved.firstIndex(where: { existing in
                      guard let prior = existing.balloonShape else { return false }
                      return prior.bounds.intersectionArea(with: shape.bounds) / max(prior.bounds.area, shape.bounds.area) > 0.85
                  }) else { resolved.append(block); continue }
            resolved[index].originalText += " " + block.originalText
            resolved[index].box = resolved[index].box.union(block.box)
        }
        return resolved
    }

    public static func merge(existing: [TextBlock], effects: [TextBlock], opticalCandidates: [TextBlock]) -> (blocks: [TextBlock], extras: [TextBlock], unverified: Int) {
        let candidates = opticalCandidates.filter { $0.confidence >= 0.35 && TextLanguageDetector.containsJapanese($0.originalText) }
        let grounded = effects.compactMap { effect -> TextBlock? in
            let matches = candidates.filter { normalized($0.originalText) == normalized(effect.originalText) && distance($0.box, effect.box) < 0.25 }
            guard let match = matches.min(by: { distance($0.box, effect.box) < distance($1.box, effect.box) }) else {
                return existing.contains { normalized($0.originalText) == normalized(effect.originalText) && overlaps($0.box, effect.box) } ? effect : nil
            }
            var resolved = effect; resolved.box = match.box; resolved.sourceIsVertical = match.sourceIsVertical
            resolved.confidence = match.confidence
            return resolved
        }
        var enriched = existing
        for effect in grounded {
            if let index = enriched.firstIndex(where: { overlaps(effect.box, $0.box) && normalized(effect.originalText) == normalized($0.originalText) }) {
                enriched[index].textKind = .soundEffect; enriched[index].rotationDegrees = effect.rotationDegrees
            }
        }
        var extras: [TextBlock] = []
        for candidate in grounded + candidates {
            guard candidate.confidence >= 0.35 && TextLanguageDetector.containsJapanese(candidate.originalText),
                  !enriched.contains(where: { overlaps(candidate.box, $0.box)
                      || (normalized($0.originalText).contains(normalized(candidate.originalText)) && distance(candidate.box, $0.box) < 0.25) }),
                  !extras.contains(where: { overlaps(candidate.box, $0.box) }) else { continue }
            extras.append(candidate)
        }
        return (enriched + extras, extras, effects.count - grounded.count)
    }
    private static func normalized(_ text: String) -> String { text.filter { !$0.isWhitespace } }
    private static func distance(_ a: TextBox, _ b: TextBox) -> Double {
        hypot(a.x + a.width / 2 - b.x - b.width / 2, a.y + a.height / 2 - b.y - b.height / 2)
    }
    private static func overlaps(_ a: TextBox, _ b: TextBox) -> Bool {
        let smaller = min(a.area, b.area)
        return smaller > 0 && a.intersectionArea(with: b) / smaller > 0.25
    }
}
