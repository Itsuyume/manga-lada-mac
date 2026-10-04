import AppKit
import MangaLadaCore

extension TranslatedImageRenderer {
    /// Unchanged, unstyled punctuation keeps the source artwork in its OCR bounds.
    /// Overlapping text or user-defined placement must continue through normal typesetting.
    func originalPunctuationRegions(in blocks: [TextBlock], imageSize: NSSize) -> [(index: Int, rect: NSRect)] {
        let canvas = NSRect(origin: .zero, size: imageSize)
        return blocks.enumerated().compactMap { index, block in
            guard PunctuationArtworkPolicy.isCandidate(block), block.userDefinedOriginalText == false else { return nil }
            // Preserve antialiased edge pixels just outside a tightly detected OCR box.
            let rect = pixelRect(for: block.box, imageSize: imageSize).integral.insetBy(dx: -2, dy: -2).intersection(canvas)
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
        guard pixelBackedSize(for: original) == imageSize else { throw TranslatedImageRenderError.originalImageSizeMismatch }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .none
        for (_, rect) in regions {
            // NSImage's source rectangle uses points; OCR bounds use the original pixel grid.
            let sourceRect = NSRect(x: rect.minX / imageSize.width * original.size.width,
                                    y: rect.minY / imageSize.height * original.size.height,
                                    width: rect.width / imageSize.width * original.size.width,
                                    height: rect.height / imageSize.height * original.size.height)
            original.draw(in: rect, from: sourceRect, operation: .copy, fraction: 1)
        }
        return Set(regions.map { $0.index })
    }
}
