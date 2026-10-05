import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkLetteringDirections(in root: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 360, pixelsHigh: 480, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 360, height: 480).fill(); NSGraphicsContext.restoreGraphicsState()
        let source = NSImage(size: bitmap.size); source.addRepresentation(bitmap)
        let before = source.tiffRepresentation
        let box = TextBox(x: 0.18, y: 0.14, width: 0.64, height: 0.72)
        var block = TextBlock(box: box, originalText: "ドキドキ", translatedText: "두근두근", sourceIsVertical: true,
                              detectedFontSize: 44, textKind: .soundEffect, effectStyleID: "custom")
        let vertical = try letteringRender(source, block: block)
        let verticalBounds = try letteringBounds(vertical)
        try require(verticalBounds.height > verticalBounds.width * 3, "Vertical source effect stayed horizontal.")
        block.textDirection = .horizontal
        let horizontal = try letteringRender(source, block: block)
        let horizontalBounds = try letteringBounds(horizontal)
        try require(horizontalBounds.width > horizontalBounds.height * 3, "Manual horizontal override ignored.")
        block.fontScale = 1
        try require(try letteringRender(source, block: block).tiffRepresentation == horizontal.tiffRepresentation,
                    "100 percent changed the automatic fitted size.")
        block.fontScale = nil
        block.textDirection = .vertical; block.sourceIsVertical = false
        try require(try letteringRender(source, block: block).tiffRepresentation == vertical.tiffRepresentation,
                    "Manual vertical override lost to source orientation.")
        block.translatedText = "두근\n두근"
        let columns = try letteringRender(source, block: block)
        let columnsBounds = try letteringBounds(columns)
        try require(columnsBounds.width > verticalBounds.width * 1.6 && columnsBounds.height < verticalBounds.height * 0.7,
                    "Explicit vertical columns lost their order or line break.")
        block.translatedText = "두근두근"; block.textDirection = .horizontal
        block.fontScale = 0.8
        let small = try letteringBounds(letteringRender(source, block: block))
        block.fontScale = 1.2
        let large = try letteringBounds(letteringRender(source, block: block))
        try require(large.width > small.width * 1.3 && large.height > small.height * 1.3, "Per-region font size had no visible effect.")
        block.fontScale = nil; block.textDirection = .vertical; block.sourceIsVertical = true
        block.textOffset = .init(x: 0.1, y: -0.08)
        let moved = try letteringBounds(letteringRender(source, block: block))
        try require(abs(moved.minX - verticalBounds.minX - 36) <= 1 && abs(moved.minY - verticalBounds.minY + 38.4) <= 1,
                    "Dragging did not move glyph pixels by the normalized page distance.")
        block.textOffset = nil
        try checkRotatedVerticalEffects(source: source, block: block)
        try checkVerticalDialogue(source: source, block: block)
        try require(source.tiffRepresentation == before, "Manual lettering changed the clean source.")
        for (name, image) in [("vertical", vertical), ("horizontal", horizontal), ("columns", columns)] {
            guard let rep = image.representations.first as? NSBitmapImageRep else { throw CocoaError(.coderReadCorrupt) }
            try rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("lettering-\(name).png"))
        }
        print("Lettering pixel checks passed: upright/horizontal/columns, exact movement, size, rotation, contour containment, source preservation")
    }

    @MainActor
    private static func checkRotatedVerticalEffects(source: NSImage, block: TextBlock) throws {
        for style in try SoundEffectLibrary.standard().styles {
            var rotated = block; rotated.effectStyleID = style.id; rotated.rotationDegrees = 18
            let bounds = try letteringBounds(letteringRender(source, block: rotated))
            try require(bounds.minX >= 64 && bounds.maxX <= 296 && bounds.minY >= 67 && bounds.maxY <= 413,
                        "Rotated vertical effect escaped its region: \(style.id).")
        }
    }

    @MainActor
    private static func checkVerticalDialogue(source: NSImage, block: TextBlock) throws {
        var speech = block; speech.textKind = .dialogue; speech.translatedText = "잠깐만"
        speech.effectStyleID = nil; speech.textDirection = .vertical
        let box = TextBox(x: 0.34, y: 0.2, width: 0.32, height: 0.6)
        let rows = (0...96).map { step -> BalloonShapeRow in
            let y = Double(step) / 96, half = 0.16 * sqrt(max(0, 1 - pow(y * 2 - 1, 2)))
            return .init(y: 0.2 + y * 0.6, left: 0.5 - half, right: 0.5 + half)
        }
        speech.box = box; speech.balloonShape = .init(bounds: box, rows: rows)
        let bounds = try letteringBounds(letteringRender(source, block: speech))
        try require(bounds.height > bounds.width * 2, "Vertical dialogue did not stack upright glyphs.")
        speech.fontScale = 1
        try require(try letteringBounds(letteringRender(source, block: speech)) == bounds, "100 percent changed automatic dialogue size.")
        speech.fontScale = 0.8
        let smaller = try letteringBounds(letteringRender(source, block: speech))
        try require(smaller.width < bounds.width && smaller.height < bounds.height, "Manual decrease did not reduce dialogue pixels.")
        speech.translatedText = String(repeating: "너무 긴 문장 ", count: 30); speech.fontScale = 2.4
        do {
            _ = try letteringRender(source, block: speech)
            try require(false, "Manual oversized text was silently shrunk or clipped.")
        } catch TranslatedImageRenderError.textDoesNotFit { }
    }

    @MainActor
    private static func letteringRender(_ source: NSImage, block: TextBlock) throws -> NSImage {
        try TranslatedImageRenderer().render(image: source, blocks: [block], backgroundStyle: .none)
    }
    @MainActor
    private static func letteringBounds(_ image: NSImage) throws -> CGRect {
        guard let bounds = darkPixelBounds(image: image, normalizedArea: CGRect(x: 0, y: 0, width: 1, height: 1)) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return bounds
    }
}
