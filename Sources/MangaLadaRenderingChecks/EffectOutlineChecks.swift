import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkEffectOutlineCoverage() throws {
        for name in ["NanumMyeongjo", "NanumBrush", "BlackHanSans-Regular"] {
            for size in [20.0, 44.0, 72.0] {
                try checkEffectFill(fontName: name, size: size)
            }
        }
        try checkEffectHalos()
        print("Effect outline checks passed: original glyph strokes retained at 20, 44 and 72 points across three font families")
    }

    @MainActor
    private static func checkEffectFill(fontName: String, size: Double) throws {
        let reference = effectBitmap()
        let sourceBitmap = effectBitmap()
        let source = NSImage(size: sourceBitmap.size); source.addRepresentation(sourceBitmap)
        let before = source.tiffRepresentation
        let text = "두근두근"
        let font = NSFont(name: fontName, size: size)!
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byCharWrapping
        let fill = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black,
                                                                .paragraphStyle: paragraph, .kern: 0])
        let bounds = fill.boundingRect(with: NSSize(width: 392, height: CGFloat.greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading]).integral
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: reference)
        fill.draw(in: NSRect(x: (400 - bounds.width) / 2, y: (220 - bounds.height) / 2, width: bounds.width, height: bounds.height))
        NSGraphicsContext.restoreGraphicsState()
        let block = TextBlock(box: TextBox(x: 0, y: 0, width: 1, height: 1), originalText: "ドキドキ", translatedText: text,
                              detectedFontSize: size, textKind: .soundEffect, effectStyleID: "custom")
        let typography = MangaTypography(effectFontName: fontName)
        let rendered = try TranslatedImageRenderer(typography: typography).render(image: source, blocks: [block], backgroundStyle: .none)
        guard let output = rendered.representations.first as? NSBitmapImageRep else { throw CocoaError(.coderReadCorrupt) }
        let coverage = effectFillCoverage(reference: reference, output: output)
        try require(coverage.expected > 10, "Effect reference contains no solid glyph strokes.")
        try require(Double(coverage.retained) / Double(coverage.expected) >= 0.95,
                    "Effect outline erased glyph strokes for \(fontName) at \(size)pt: \(coverage.retained)/\(coverage.expected) retained.")
        print("Effect fill \(fontName) \(size)pt: \(coverage.retained)/\(coverage.expected) solid glyph pixels retained")
        try require(source.tiffRepresentation == before, "Effect outline changed the source image.")
    }

    @MainActor
    private static func effectBitmap(background: NSColor = .white) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 220, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        background.setFill(); NSRect(x: 0, y: 0, width: 400, height: 220).fill()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func effectFillCoverage(reference: NSBitmapImageRep, output: NSBitmapImageRep) -> (expected: Int, retained: Int) {
        var expected = 0, retained = 0
        for y in 0..<reference.pixelsHigh {
            for x in 0..<reference.pixelsWide where reference.colorAt(x: x, y: y)!.redComponent < 0.1 {
                expected += 1
                if output.colorAt(x: x, y: y)!.redComponent < 0.2 { retained += 1 }
            }
        }
        return (expected, retained)
    }

    @MainActor
    private static func checkEffectHalos() throws {
        let box = TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        for (style, background) in [("custom", NSColor.black), ("shout", NSColor.white)] {
            let sourceBitmap = effectBitmap(background: background)
            let source = NSImage(size: sourceBitmap.size); source.addRepresentation(sourceBitmap)
            let block = TextBlock(box: box, originalText: "ドーン", translatedText: "쾅!", detectedFontSize: 100,
                                  textKind: .soundEffect, rotationDegrees: 25, effectStyleID: style)
            let renderer = TranslatedImageRenderer(typography: MangaTypography(effectFontName: "NanumMyeongjo"))
            let image = try renderer.render(image: source, blocks: [block], backgroundStyle: .none)
            guard let output = image.representations.first as? NSBitmapImageRep else { throw CocoaError(.coderReadCorrupt) }
            let expected = style == "custom" ? 0.0 : 1.0
            let changes = effectHaloChanges(output: output, background: expected)
            try require(changes.contrast > 40, "Effect halo disappeared against its background for \(style).")
            try require(changes.outside == 0, "Rotated effect painted outside its assigned region for \(style).")
        }
        print("Effect halo checks passed: light outline on black, hollow outline on white, rotated region containment")
    }

    private static func effectHaloChanges(output: NSBitmapImageRep, background: Double) -> (contrast: Int, outside: Int) {
        var contrast = 0, outside = 0
        for y in 0..<output.pixelsHigh {
            for x in 0..<output.pixelsWide {
                let delta = abs(output.colorAt(x: x, y: y)!.redComponent - background)
                if delta > 0.75 { contrast += 1 }
                if delta > 0.01, x < 40 || x >= 360 || y < 22 || y >= 198 { outside += 1 }
            }
        }
        return (contrast, outside)
    }
}
