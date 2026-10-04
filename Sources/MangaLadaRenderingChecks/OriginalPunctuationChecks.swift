import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkOriginalPunctuation(in root: URL) throws {
        let box = TextBox(x: 0.4, y: 0.55, width: 0.2, height: 0.2)
        let punctuation = TextBlock(box: box, originalText: " ・ ", translatedText: "・", detectedFontSize: 18,
                                    rotationDegrees: -5, userDefinedOriginalText: false)
        let caption = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.2), originalText: "静かになった。",
                                translatedText: "조용해졌다.", detectedFontSize: 32, textKind: .caption)
        let renderer = TranslatedImageRenderer()
        for pointScale in [1.0, 0.5] {
            let original = makePunctuationImage(cleaned: false, pointScale: pointScale)
            let clean = makePunctuationImage(cleaned: true, pointScale: pointScale)
            let originalBytes = original.tiffRepresentation, cleanBytes = clean.tiffRepresentation
            let reference = try punctuationPixels(renderer.render(image: original, blocks: []))
            var blank = punctuation; blank.originalText = ""; blank.translatedText = ""
            let baseline = try punctuationPixels(renderer.render(image: clean, blocks: [caption, blank], backgroundStyle: .none))
            let output = try renderer.render(image: clean, blocks: [caption, punctuation], backgroundStyle: .none, originalImage: original)
            let pixels = try punctuationPixels(output)
            var restored = 0
            for y in 0..<400 {
                for x in 0..<400 {
                    let index = y * 400 + x
                    let inside = (160..<240).contains(x) && (220..<300).contains(y)
                    try require(pixels[index] == (inside ? reference[index] : baseline[index]), "Original punctuation shifted, resized or changed unrelated pixels at \(x),\(y).")
                    if inside && pixels[index] != baseline[index] { restored += 1 }
                }
            }
            try require(restored > 600, "Original punctuation restoration did not restore the large source glyph.")
            try require(original.tiffRepresentation == originalBytes && clean.tiffRepresentation == cleanBytes, "Rendering mutated an input image.")
            if pointScale == 1 { try output.tiffRepresentation!.write(to: root.appendingPathComponent("original-punctuation.tiff")) }
        }
        let original = makePunctuationImage(cleaned: false), clean = makePunctuationImage(cleaned: true)
        try checkTightPunctuationBounds(renderer: renderer, original: original, clean: clean, punctuation: punctuation)
        try checkPunctuationEdits(renderer: renderer, original: original, clean: clean, punctuation: punctuation, caption: caption)
        try checkPunctuationFiles(root: root, original: original, clean: clean, punctuation: punctuation, caption: caption)
        print("Original punctuation passed: exact source pixels, pixel/point scales, edits/styles/placement, overlap, missing/mismatched original and unchanged inputs")
    }

    @MainActor
    private static func checkTightPunctuationBounds(renderer: TranslatedImageRenderer, original: NSImage,
                                                    clean: NSImage, punctuation: TextBlock) throws {
        var tight = punctuation
        // OCR may stop before the antialiased fringe as well as the final dark row.
        tight.box = TextBox(x: 184.0 / 400, y: 244.0 / 400, width: 32.0 / 400, height: 30.0 / 400)
        let expected = try punctuationPixels(renderer.render(image: original, blocks: []))
        let actual = try punctuationPixels(renderer.render(image: clean, blocks: [tight], originalImage: original))
        try require(actual == expected, "Tight OCR bounds clipped the final row of an original punctuation glyph.")
        let neighbor = TextBlock(box: TextBox(x: 216.0 / 400, y: 244.0 / 400, width: 0.2, height: 0.1),
                                 originalText: "音", translatedText: "소리", detectedFontSize: 18)
        let overlapping = try punctuationPixels(renderer.render(image: clean, blocks: [tight, neighbor], originalImage: original))
        let typeset = try punctuationPixels(renderer.render(image: clean, blocks: [tight, neighbor]))
        try require(overlapping == typeset, "Restoration margin overlapped neighboring text.")
    }

    @MainActor
    private static func checkPunctuationEdits(renderer: TranslatedImageRenderer, original: NSImage, clean: NSImage,
                                             punctuation: TextBlock, caption: TextBlock) throws {
        var edited = punctuation; edited.translatedText = "!"
        var placed = punctuation; placed.userDefinedBounds = punctuation.box
        var classified = punctuation; classified.userDefinedTextKind = true
        var styled = punctuation; styled.effectStyleID = "impact"; styled.textKind = .soundEffect
        var word = punctuation; word.originalText = "音"; word.translatedText = "소리"
        var corrected = punctuation; corrected.originalText = "!"; corrected.translatedText = "!"; corrected.userDefinedOriginalText = true
        for block in [edited, placed, classified, styled, word, corrected] {
            let expected = try punctuationPixels(renderer.render(image: clean, blocks: [caption, block], backgroundStyle: .none))
            let actual = try punctuationPixels(renderer.render(image: clean, blocks: [caption, block], backgroundStyle: .none, originalImage: original))
            try require(actual == expected, "Original glyph restoration overrode a user edit, style, placement or lexical translation.")
        }
        for bounds in [false, true] {
            var adjacent = caption
            if bounds { adjacent.userDefinedBounds = TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8) }
            else { adjacent.box = punctuation.box }
            let expected = try punctuationPixels(renderer.render(image: clean, blocks: [adjacent, punctuation], backgroundStyle: .none))
            let actual = try punctuationPixels(renderer.render(image: clean, blocks: [adjacent, punctuation], backgroundStyle: .none, originalImage: original))
            try require(actual == expected, "Punctuation restored Japanese pixels over another text region or manual placement.")
        }
        let empty = try punctuationPixels(renderer.render(image: clean, blocks: [], originalImage: original))
        let baseline = try punctuationPixels(renderer.render(image: clean, blocks: []))
        try require(empty == baseline, "An empty page restored unrelated artwork.")
    }

    @MainActor
    private static func checkPunctuationFiles(root: URL, original: NSImage, clean: NSImage, punctuation: TextBlock, caption: TextBlock) throws {
        let sourceURL = root.appendingPathComponent("punctuation-source.tiff"), cleanURL = root.appendingPathComponent("punctuation-clean.tiff")
        let destination = root.appendingPathComponent("punctuation-output.png"), missing = root.appendingPathComponent("missing-original.png")
        try original.tiffRepresentation!.write(to: sourceURL); try clean.tiffRepresentation!.write(to: cleanURL)
        let renderer = TranslatedImageRenderer()
        var translation = PageTranslation(imageURL: sourceURL, imageFingerprint: "punctuation", sourceLanguage: .japanese, targetLanguage: .korean, blocks: [caption, punctuation])
        _ = try renderer.writePNG(sourceImageURL: cleanURL, translation: translation, destinationURL: destination,
                                  backgroundStyle: .none, originalImageURL: sourceURL)
        let saved = try Data(contentsOf: destination)
        let image = NSImage(contentsOf: destination)!
        let direct = try renderer.render(image: clean, blocks: translation.blocks, backgroundStyle: .none, originalImage: original)
        try require(try punctuationPixels(image) == punctuationPixels(direct), "PNG saving lost original punctuation pixels.")
        do {
            _ = try renderer.writePNG(sourceImageURL: cleanURL, translation: translation, destinationURL: destination,
                                      backgroundStyle: .none, originalImageURL: missing)
            try require(false, "Missing original image was silently ignored.")
        } catch TranslatedImageRenderError.imageLoadFailed(let failed) { try require(failed == missing, "Wrong image load error.") }
        let small = NSImage(size: NSSize(width: 10, height: 10))
        do {
            _ = try renderer.render(image: clean, blocks: translation.blocks, backgroundStyle: .none, originalImage: small)
            try require(false, "Mismatched source dimensions were silently scaled.")
        } catch TranslatedImageRenderError.originalImageSizeMismatch { }
        try require(try Data(contentsOf: destination) == saved, "Original-image failure replaced the completed output.")
        translation.blocks = [caption]
        _ = try renderer.writePNG(sourceImageURL: cleanURL, translation: translation, destinationURL: root.appendingPathComponent("caption-only.png"),
                                  backgroundStyle: .none, originalImageURL: missing)
    }

    @MainActor
    private static func makePunctuationImage(cleaned: Bool, pointScale: Double = 1) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 400, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 400, height: 400).fill()
        NSColor.black.setFill()
        for x in [100, 184, 268] where !cleaned || x != 184 {
            NSBezierPath(ovalIn: NSRect(x: x, y: 124, width: 32, height: 32)).fill()
        }
        NSColor(calibratedRed: 0.4, green: 0.7, blue: 0.9, alpha: 1).setFill()
        NSRect(x: 30, y: 20, width: 90, height: 20).fill()
        NSGraphicsContext.restoreGraphicsState()
        let size = NSSize(width: 400 * pointScale, height: 400 * pointScale)
        bitmap.size = size
        let image = NSImage(size: size); image.addRepresentation(bitmap)
        return image
    }

    @MainActor
    private static func punctuationPixels(_ image: NSImage) throws -> [UInt32] {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { throw CocoaError(.coderReadCorrupt) }
        try require(bitmap.pixelsWide == 400 && bitmap.pixelsHigh == 400, "Punctuation rendering changed pixel dimensions.")
        return (0..<400).flatMap { y in (0..<400).map { x in
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let components = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            return components.reduce(UInt32(0)) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
        } }
    }
}
