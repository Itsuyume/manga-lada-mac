import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkOriginalRegions(in root: URL) throws {
        let renderer = TranslatedImageRenderer()
        let first = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.3, height: 0.3), originalText: "また明日。",
            translatedText: "내일 봐!", detectedFontSize: 25, textKind: .dialogue)
        let second = TextBlock(box: .init(x: 0.55, y: 0.1, width: 0.35, height: 0.3), originalText: "ありがとう",
            translatedText: "고마워!", detectedFontSize: 25, textKind: .dialogue)
        var kept = first; kept.keepsOriginal = true
        for scale in [1.0, 0.5] {
            let original = makeOriginalRegionImage(pointScale: scale), clean = makeOriginalRegionImage(clean: true, pointScale: scale)
            let before = original.tiffRepresentation, cleanBefore = clean.tiffRepresentation
            let source = try imagePixels(renderer.render(image: original, blocks: []))
            let baseline = try imagePixels(renderer.render(image: clean, blocks: [first, second], backgroundStyle: .none))
            let result = try imagePixels(renderer.render(image: clean, blocks: [kept, second], backgroundStyle: .none, originalImage: original))
            var uncertain = first; uncertain.recognitionAlternatives = ["また明日", "また来週"]
            try require(try imagePixels(renderer.render(image: clean, blocks: [uncertain, second], backgroundStyle: .none,
                                                        originalImage: original)) == result, "Uncertain OCR erased artwork or hid its neighboring translation.")
            try require(result.count == 160_000 && source.count == result.count, "Original restoration changed pixel dimensions.")
            for y in 0..<400 {
                for x in 0..<400 {
                    let index = y * 400 + x, inside = (38..<162).contains(x) && (38..<162).contains(y)
                    try require(result[index] == (inside ? source[index] : baseline[index]), "Restoring a region changed its neighbor or left translated pixels.")
                }
            }
            var moved = kept; moved.textOffset = .init(x: 0.4, y: 0.4); moved.textLayoutBounds = second.box
            moved.textDirection = .vertical; moved.fontScale = 2.4
            try require(try imagePixels(renderer.render(image: clean, blocks: [moved, second], backgroundStyle: .none,
                                                        originalImage: original)) == result, "Original restoration used translated placement or styling.")
            var keptSecond = second; keptSecond.keepsOriginal = true; keptSecond.translatedText = ""
            try require(try imagePixels(renderer.render(image: clean, blocks: [kept, keptSecond], backgroundStyle: .none,
                                                        originalImage: original)) == source, "All-original page did not exactly match the source pixels.")
            var restored = kept; restored.keepsOriginal = nil
            try require(try imagePixels(renderer.render(image: clean, blocks: [restored, second], backgroundStyle: .none,
                                                        originalImage: original)) == baseline, "Restoring translation changed its former appearance.")
            try require(original.tiffRepresentation == before && clean.tiffRepresentation == cleanBefore, "Original restoration mutated input images.")
        }
        try checkOriginalOverlap(renderer: renderer, kept: kept, neighbor: second)
        try checkOriginalRegionFailures(root: root, renderer: renderer, blocks: [kept, second])
        print("Original-region rendering passed: exact source pixels, adjacent translation, undo, all-original, moved lettering, overlap, missing source, atomic output")
    }

    @MainActor
    private static func checkOriginalOverlap(renderer: TranslatedImageRenderer, kept: TextBlock, neighbor: TextBlock) throws {
        let original = makeOriginalRegionImage(), clean = makeOriginalRegionImage(clean: true)
        var wide = kept
        wide.userDefinedBounds = .init(x: 0.08, y: 0.08, width: 0.85, height: 0.35)
        let output = try imagePixels(renderer.render(image: clean, blocks: [wide, neighbor], backgroundStyle: .none, originalImage: original))
        let reference = try imagePixels(renderer.render(image: clean, blocks: [neighbor], backgroundStyle: .none))
        for y in 38..<162 {
            for x in 218..<362 {
                try require(output[y * 400 + x] == reference[y * 400 + x], "Overlapping original selection resurrected a neighbor's Japanese source.")
            }
        }
    }

    @MainActor
    private static func checkOriginalRegionFailures(root: URL, renderer: TranslatedImageRenderer, blocks: [TextBlock]) throws {
        let original = makeOriginalRegionImage(), clean = makeOriginalRegionImage(clean: true)
        do {
            _ = try renderer.render(image: clean, blocks: blocks, backgroundStyle: .none)
            try require(false, "Missing original produced a blank region.")
        } catch TranslatedImageRenderError.originalImageRequired { }
        do {
            _ = try renderer.render(image: clean, blocks: blocks, originalImage: NSImage(size: .init(width: 10, height: 10)))
            try require(false, "Mismatched original was silently rescaled.")
        } catch TranslatedImageRenderError.originalImageSizeMismatch { }
        let sourceURL = root.appendingPathComponent("kept-source.tiff"), cleanURL = root.appendingPathComponent("kept-clean.tiff")
        let destination = root.appendingPathComponent("kept-output.png")
        try original.tiffRepresentation!.write(to: sourceURL); try clean.tiffRepresentation!.write(to: cleanURL)
        var page = PageTranslation(imageURL: sourceURL, imageFingerprint: "kept", sourceLanguage: .japanese, targetLanguage: .korean, blocks: blocks)
        _ = try renderer.writePNG(sourceImageURL: cleanURL, translation: page, destinationURL: destination, backgroundStyle: .none)
        let saved = try Data(contentsOf: destination)
        page.imageURL = root.appendingPathComponent("missing-source.png")
        do {
            _ = try renderer.writePNG(sourceImageURL: cleanURL, translation: page, destinationURL: destination, backgroundStyle: .none)
            try require(false, "Missing original file was hidden.")
        } catch TranslatedImageRenderError.imageLoadFailed { }
        try require(try Data(contentsOf: destination) == saved, "Failed restoration replaced a saved image.")
    }

    @MainActor
    private static func makeOriginalRegionImage(clean: Bool = false, pointScale: Double = 1) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400, pixelsHigh: 400, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 400, height: 400).fill()
        if !clean {
            NSColor.black.setFill(); NSRect(x: 64, y: 264, width: 38, height: 68).fill()
            NSColor.blue.setFill(); NSRect(x: 246, y: 264, width: 38, height: 68).fill()
        }
        NSColor.gray.setFill(); NSRect(x: 20, y: 20, width: 360, height: 40).fill()
        NSGraphicsContext.restoreGraphicsState()
        let size = NSSize(width: 400 * pointScale, height: 400 * pointScale)
        bitmap.size = size
        let image = NSImage(size: size); image.addRepresentation(bitmap)
        return image
    }
}
