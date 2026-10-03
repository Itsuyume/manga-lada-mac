import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkDarkCaptionAndManualContour() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 1200, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 900, height: 1200).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: bitmap.size); image.addRepresentation(bitmap)
        let box = TextBox(x: 0.2, y: 0.3, width: 0.5, height: 0.2)
        let shape = BalloonShape(bounds: box, rows: (0...96).map { index in
            BalloonShapeRow(y: box.y + box.height * Double(index) / 96, left: box.x, right: box.x + box.width)
        })
        let block = TextBlock(box: box, originalText: "置いてあった", translatedText: "마침 놓여 있던 담요.", textKind: .caption, balloonShape: shape)
        let rendered = try TranslatedImageRenderer().render(image: image, blocks: [block], backgroundStyle: .none)
        guard let output = rendered.representations[0] as? NSBitmapImageRep else { throw CocoaError(.coderReadCorrupt) }
        var white = 0
        for y in Int(box.y * 1200)..<Int((box.y + box.height) * 1200) {
            for x in Int(box.x * 900)..<Int((box.x + box.width) * 900) {
                if output.colorAt(x: x, y: y)!.redComponent > 0.85 { white += 1 }
            }
        }
        try require(white > 100, "Dark caption used invisible black text.")
        let before = bitmap.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!.redComponent
        let after = output.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!.redComponent
        try require(abs(before - after) < 0.02, "Contrast changed unrelated pixels: \(before) -> \(after).")
        let clipped = shape.clipped(to: TextBox(x: 0.4, y: 0.3, width: 0.3, height: 0.2))!
        try require(clipped.rows.allSatisfy({ $0.left >= 0.4 && $0.right <= 0.7 }), "Manual selection escaped its contour.")
        try require(shape.clipped(to: TextBox(x: 0.9, y: 0.9, width: 0.05, height: 0.05)) == nil, "Disjoint manual box invented a balloon.")
        let narrow = TextBox(x: 0.1, y: 0.2, width: 49 / 1419, height: 164 / 2000)
        let tinyShape = BalloonShape(bounds: narrow, rows: (0...96).map { index in
            let fraction = Double(index) / 96
            let half = narrow.width / 2 * sqrt(max(0, 1 - pow(fraction * 2 - 1, 2)))
            return BalloonShapeRow(y: narrow.y + narrow.height * fraction, left: narrow.x + narrow.width / 2 - half,
                                   right: narrow.x + narrow.width / 2 + half)
        })
        let page = NSImage(size: NSSize(width: 1419, height: 2000))
        page.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1419, height: 2000).fill(); page.unlockFocus()
        _ = try TranslatedImageRenderer().render(image: page, blocks: [TextBlock(box: narrow, originalText: "キモ", translatedText: "역겨워.",
            sourceIsVertical: true, detectedFontSize: 37, balloonShape: tinyShape)], backgroundStyle: .none)
        print("Dark caption checks passed: white glyphs, unchanged background, manual bounds intersect contour")
    }
}
