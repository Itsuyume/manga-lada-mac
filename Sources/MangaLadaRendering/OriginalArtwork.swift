import AppKit
import MangaLadaCore

extension TranslatedImageRenderer {
    /// Composite from the original pixel grid, never from an already translated image.
    func copyArtwork(_ image: NSImage, regions: [NSRect], imageSize: NSSize) throws {
        guard pixelBackedSize(for: image) == imageSize else { throw TranslatedImageRenderError.originalImageSizeMismatch }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .none
        for rect in regions {
            let source = NSRect(x: rect.minX / imageSize.width * image.size.width,
                                y: rect.minY / imageSize.height * image.size.height,
                                width: rect.width / imageSize.width * image.size.width,
                                height: rect.height / imageSize.height * image.size.height)
            image.draw(in: rect, from: source, operation: .copy, fraction: 1)
        }
    }

    func restoreOriginalSelections(_ original: NSImage?, blocks: [TextBlock], imageSize: NSSize) throws {
        let kept = blocks.filter { $0.preservesOriginalArtwork }
        guard !kept.isEmpty else { return }
        guard let original else { throw TranslatedImageRenderError.originalImageRequired }
        let canvas = NSRect(origin: .zero, size: imageSize)
        if kept.count == blocks.count {
            try copyArtwork(original, regions: [canvas], imageSize: imageSize)
            return
        }
        // Keep neighbors' erased source text erased. Their Korean is drawn afterwards.
        let protected = blocks.filter { !$0.preservesOriginalArtwork }.map {
            pixelRect(for: $0.userDefinedBounds ?? $0.box, imageSize: imageSize).integral.insetBy(dx: -2, dy: -2)
        }
        var regions: [NSRect] = []
        for block in kept {
            let bounds = block.userDefinedBounds ?? block.balloonShape?.bounds ?? block.box
            guard ImageRegionSelection.validates(bounds) else { throw TranslatedImageRenderError.invalidOriginalBounds }
            let source = pixelRect(for: bounds, imageSize: imageSize).integral.insetBy(dx: -2, dy: -2).intersection(canvas)
            let pieces = protected.reduce([source]) { remaining, neighbor in
                remaining.flatMap { subtract(neighbor, from: $0) }
            }
            regions.append(contentsOf: pieces)
        }
        try copyArtwork(original, regions: regions, imageSize: imageSize)
    }

    private func subtract(_ other: NSRect, from rect: NSRect) -> [NSRect] {
        let overlap = rect.intersection(other)
        guard !overlap.isNull, !overlap.isEmpty else { return [rect] }
        return [
            NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
            NSRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
            NSRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
            NSRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height)
        ].filter { !$0.isEmpty }
    }
}
