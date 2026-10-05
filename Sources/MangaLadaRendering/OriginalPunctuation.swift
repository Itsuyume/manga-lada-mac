import AppKit
import MangaLadaCore

extension TranslatedImageRenderer {
    /// Unchanged, unstyled punctuation keeps artwork in verified automatic or manual OCR bounds.
    /// Unknown placement or overlapping text continues through normal typesetting.
    func originalPunctuationRegions(in blocks: [TextBlock], imageSize: NSSize) -> [(index: Int, rect: NSRect)] {
        let canvas = NSRect(origin: .zero, size: imageSize)
        return blocks.enumerated().compactMap { index, block in
            guard block.keepsOriginal != true, let bounds = PunctuationArtworkPolicy.sourceBounds(for: block),
                  block.userDefinedOriginalText == false else { return nil }
            // Preserve antialiased edge pixels just outside a tightly detected OCR box.
            var rect = pixelRect(for: bounds, imageSize: imageSize).integral.insetBy(dx: -2, dy: -2).intersection(canvas)
            if let selected = block.userDefinedBounds { rect = rect.intersection(pixelRect(for: selected, imageSize: imageSize)) }
            let overlaps = blocks.enumerated().contains { otherIndex, other in
                guard otherIndex != index else { return false }
                let occupied = other.userDefinedBounds ?? other.balloonShape?.bounds ?? other.box
                return rect.intersects(pixelRect(for: occupied, imageSize: imageSize).integral)
            }
            return overlaps ? nil : (index, rect)
        }
    }

    func restoreOriginalPunctuation(_ original: NSImage?, blocks: [TextBlock], imageSize: NSSize) throws -> Set<Int> {
        guard let original else { return [] }
        let regions = originalPunctuationRegions(in: blocks, imageSize: imageSize)
        guard !regions.isEmpty else { return [] }
        try copyArtwork(original, regions: regions.map(\.rect), imageSize: imageSize)
        return Set(regions.map { $0.index })
    }
}
