import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkShapeAndConsistency(in root: URL) throws {
        let image = NSImage(size: NSSize(width: 900, height: 600))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 600).fill(); image.unlockFocus()
        let rectangles = [TextBox(x: 0.10, y: 0.15, width: 0.32, height: 0.65), TextBox(x: 0.58, y: 0.15, width: 0.32, height: 0.65)]
        let blocks = rectangles.enumerated().map { index, box in
            TextBlock(box: box, originalText: "少し休もうか", translatedText: "... 조금 쉬었다 갈까?", sourceIsVertical: index == 0,
                      detectedFontSize: index == 0 ? 18 : 40, balloonShape: ellipse(box))
        }
        let output = try TranslatedImageRenderer().render(image: image, blocks: blocks, backgroundStyle: .none)
        let left = darkPixelBounds(image: output, normalizedArea: CGRect(x: 0.1, y: 0.15, width: 0.32, height: 0.65))!
        let right = darkPixelBounds(image: output, normalizedArea: CGRect(x: 0.58, y: 0.15, width: 0.32, height: 0.65))!
        try require(abs(left.width - right.width) < 3 && abs(left.height - right.height) < 3,
                    "Source direction or detected ink size changed the dialogue's typography.")
        try require(left.width > left.height, "Short Korean dialogue became vertical.")
        let bitmap = NSBitmapImageRep(data: output.tiffRepresentation!)!
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y), color.redComponent < 0.3 else { continue }
                let px = Double(x) / Double(bitmap.pixelsWide), py = Double(y) / Double(bitmap.pixelsHigh)
                try require(rectangles.contains { box in
                    pow((px - box.x - box.width / 2) / (box.width / 2), 2) + pow((py - box.y - box.height / 2) / (box.height / 2), 2) < 0.94
                }, "Text escaped the curved balloon interior.")
            }
        }
        var oversized = blocks[0]; oversized.translatedText = String(repeating: "매우 긴 문장은 잘리면 안 됩니다. ", count: 500)
        do {
            _ = try TranslatedImageRenderer().render(image: image, blocks: [oversized], backgroundStyle: .none)
            try require(false, "Oversized text was silently cropped.")
        } catch TranslatedImageRenderError.textDoesNotFit { }
        try require(NSImage(contentsOf: root.appendingPathComponent("source.png")) != nil, "Source was lost during layout checks.")
    }

    private static func ellipse(_ box: TextBox) -> BalloonShape {
        let rows = (0...128).map { index in
            let fraction = Double(index) / 128
            let halfWidth = box.width / 2 * sqrt(max(0, 1 - pow(fraction * 2 - 1, 2)))
            return BalloonShapeRow(y: box.y + box.height * fraction,
                                   left: box.x + box.width / 2 - halfWidth, right: box.x + box.width / 2 + halfWidth)
        }
        return BalloonShape(bounds: box, rows: rows)
    }

    @MainActor
    static func checkFloatingText() throws {
        let image = NSImage(size: NSSize(width: 1419, height: 2000))
        image.lockFocus(); NSColor(calibratedWhite: 0.6, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1419, height: 2000).fill(); image.unlockFocus()
        let block = TextBlock(box: TextBox(x: 0.2, y: 0.4, width: 27 / 1419, height: 115 / 2000),
                              originalText: "アリガト", translatedText: "고마워...", sourceIsVertical: true, detectedFontSize: 27)
        let output = try TranslatedImageRenderer().render(image: image, blocks: [block], backgroundStyle: .none)
        let bounds = darkPixelBounds(image: output, normalizedArea: CGRect(x: 0.16, y: 0.4, width: 0.1, height: 0.06))
        try require((bounds?.width ?? 0) > 40, "Floating dialogue became unreadable single-character vertical text.")
        let bitmap = NSBitmapImageRep(data: output.tiffRepresentation!)!
        try require(bitmap.colorAt(x: 10, y: 10)!.redComponent > 0.59, "Floating text changed unrelated artwork.")
    }

    @MainActor
    static func checkShortVerticalSource(in root: URL) throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 1200, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 900, height: 1200).fill()
        NSColor.black.setStroke()
        let balloon = NSBezierPath(ovalIn: NSRect(x: 600, y: 730, width: 190, height: 365)); balloon.lineWidth = 3; balloon.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let source = root.appendingPathComponent("short-balloon.png"), output = root.appendingPathComponent("short-korean.png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        let bytes = try Data(contentsOf: source)
        let page = PageTranslation(imageURL: source, imageFingerprint: "short-vertical", sourceLanguage: .japanese, targetLanguage: .korean,
                                   blocks: [TextBlock(box: TextBox(x: 0.751, y: 0.126, width: 0.031, height: 0.147),
                                                      originalText: "少し休もうか", translatedText: "조금 쉬어볼까?", confidence: 1, sourceIsVertical: true, detectedFontSize: 28)])
        _ = try TranslatedImageRenderer().writePNG(sourceImageURL: source, translation: page, destinationURL: output, backgroundStyle: .none)
        let image = NSImage(contentsOf: output)!
        let bounds = darkPixelBounds(image: image, normalizedArea: CGRect(x: 0.7, y: 0.13, width: 0.145, height: 0.19))
        try require((bounds?.width ?? 0) >= 60, "Short Japanese source still forced Korean into a single-character column.")
        try require(image.representations[0].pixelsWide == 900 && image.representations[0].pixelsHigh == 1200, "Rendering changed original pixel dimensions.")
        try require(try Data(contentsOf: source) == bytes, "Renderer modified its source image.")
    }
}
