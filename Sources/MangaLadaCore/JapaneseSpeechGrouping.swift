import Foundation

/// Groups OCR columns only after geometry has separated physical balloon lobes.
public enum JapaneseSpeechGrouping {
    /// A balloon is one typesetting unit. Remove contained OCR duplicates before joining split regions.
    public static func resolve(_ blocks: [TextBlock]) -> [TextBlock] {
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

    private static func normalized(_ text: String) -> String { text.filter { !$0.isWhitespace } }
}
