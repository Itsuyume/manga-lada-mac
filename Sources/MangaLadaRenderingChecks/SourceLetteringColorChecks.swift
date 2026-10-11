import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkSourceLetteringColors(in root: URL) throws {
        try SoundEffectFonts.registerBundledFonts()
        let pink = NSColor(deviceRed: 0.88, green: 0.12, blue: 0.48, alpha: 1)
        let blue = NSColor(deviceRed: 0.08, green: 0.35, blue: 0.88, alpha: 1)
        for (name, colors) in [("pink", [pink]), ("blue", [blue]), ("ambiguous", [pink, blue]), ("blank", [])] {
            let clean = try colourFixture(colors: [])
            let source = try colourFixture(colors: colors)
            let originalURL = root.appendingPathComponent("source-colour-\(name).png")
            let cleanURL = root.appendingPathComponent("clean-colour-\(name).png")
            let outputURL = root.appendingPathComponent("translated-colour-\(name).png")
            try saveColourFixture(source, at: originalURL); try saveColourFixture(clean, at: cleanURL)
            let originalBytes = try Data(contentsOf: originalURL), cleanBytes = try Data(contentsOf: cleanURL)
            var block = TextBlock(box: TextBox(x: 0.1, y: 0.15, width: 0.8, height: 0.7), originalText: "SWISH",
                                  translatedText: "휘익", detectedFontSize: 88, textKind: .soundEffect, effectStyleID: "automatic")
            let translation = colourTranslation(block, imageURL: originalURL)
            _ = try TranslatedImageRenderer().writePNG(sourceImageURL: cleanURL, translation: translation,
                destinationURL: outputURL, backgroundStyle: .none, originalImageURL: originalURL)
            let output = NSImage(contentsOf: outputURL)!
            let changes = try colourChanges(output: output, clean: clean, box: block.box)
            try require(changes.outside == 0, "Colour lettering modified pixels outside the effect region.")
            if colors.count == 1 {
                try require(name == "pink" ? changes.pink > 200 && changes.blue == 0 : changes.blue > 200 && changes.pink == 0,
                            "Korean effect lost its source fill colour or sampled unchanged blue decorations.")
                var tight = block
                tight.box = TextBox(x: 0.2, y: 0.34, width: 0.54, height: 0.22); tight.detectedFontSize = 64
                let tightOutput = try TranslatedImageRenderer().render(image: clean, blocks: [tight], backgroundStyle: .none, originalImage: source)
                let tightChanges = try colourChanges(output: tightOutput, clean: clean, box: tight.box)
                try require(name == "pink" ? tightChanges.pink > 100 : tightChanges.blue > 100,
                            "Tight OCR bounds rejected the colour of a bold source effect.")
            } else {
                try require(changes.pink == 0 && changes.blue == 0 && changes.total > 100,
                            "Blank or ambiguous colour evidence guessed a fill colour or erased text.")
            }
            block.effectStyleID = "impact"
            let manual = try TranslatedImageRenderer().render(image: clean, blocks: [block], backgroundStyle: .none, originalImage: source)
            let manualChanges = try colourChanges(output: manual, clean: clean, box: block.box)
            try require(manualChanges.pink == 0 && manualChanges.blue == 0, "Source colours overrode a manual effect preset.")
            let missing = try TranslatedImageRenderer().render(image: clean, blocks: translation.blocks, backgroundStyle: .none)
            let missingChanges = try colourChanges(output: missing, clean: clean, box: block.box)
            try require(missingChanges.pink == 0 && missingChanges.blue == 0, "No original image invented colour evidence.")
            try require(try Data(contentsOf: originalURL) == originalBytes && Data(contentsOf: cleanURL) == cleanBytes,
                        "Colour measurement modified original or clean files.")
        }
        try checkColourSizeFailure(in: root)
        try checkColourStrokeWeight()
        try checkSolidColourRejection()
        try checkExplicitBalloonRows(in: root)
        print("Source colour checks passed: pink/blue fills, unchanged decoration exclusion, ambiguity/blank/missing source, manual presets, outside pixels, atomic size failure")
    }

    @MainActor
    private static func colourFixture(colors: [NSColor]) throws -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 500, pixelsHigh: 320, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 500, height: 320).fill()
        NSColor(deviceRed: 0.08, green: 0.35, blue: 0.88, alpha: 1).setFill()
        // Larger than the glyphs, but unchanged by erasure, including one stripe inside the effect box.
        NSRect(x: 0, y: 0, width: 500, height: 35).fill(); NSRect(x: 58, y: 56, width: 24, height: 210).fill()
        let font = NSFont(name: "AppleSDGothicNeo-Heavy", size: colors.count == 1 ? 86 : 65)!
        for (index, color) in colors.enumerated() {
            let word = NSAttributedString(string: colors.count == 1 ? "SWISH" : "AAA", attributes:
                [.font: font, .foregroundColor: color, .strokeColor: NSColor.black, .strokeWidth: -3])
            word.draw(at: NSPoint(x: colors.count == 1 ? 104 : 112 + index * 160, y: 118))
        }
        let image = NSImage(size: NSSize(width: 500, height: 320)); image.addRepresentation(bitmap)
        return image
    }

    @MainActor
    private static func saveColourFixture(_ image: NSImage, at url: URL) throws {
        let data = image.tiffRepresentation!, bitmap = NSBitmapImageRep(data: data)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: url, options: .atomic)
    }
    private static func colourTranslation(_ block: TextBlock, imageURL: URL) -> PageTranslation {
        PageTranslation(imageURL: imageURL, imageFingerprint: "colour-check", sourceLanguage: .english,
                        targetLanguage: .korean, blocks: [block])
    }
    @MainActor
    private static func checkColourStrokeWeight() throws {
        let clean = try colourFixture(colors: [])
        let pink = NSColor(deviceRed: 0.88, green: 0.12, blue: 0.48, alpha: 1)
        let blackSource = try colourFixture(colors: [.black]), pinkSource = try colourFixture(colors: [pink])
        let block = TextBlock(box: TextBox(x: 0.1, y: 0.15, width: 0.8, height: 0.7), originalText: "BOOM", translatedText: "쾅!",
                              detectedFontSize: 86, textKind: .soundEffect, effectStyleID: "automatic")
        let renderer = TranslatedImageRenderer()
        let blackOutput = try renderer.render(image: clean, blocks: [block], backgroundStyle: .none, originalImage: blackSource)
        let pinkOutput = try renderer.render(image: clean, blocks: [block], backgroundStyle: .none, originalImage: pinkSource)
        let changes = try colourChanges(output: pinkOutput, clean: clean, box: block.box)
        let blackPixels = try imagePixels(blackOutput).filter { (($0 >> 24) & 255) < 30 && (($0 >> 16) & 255) < 30 && (($0 >> 8) & 255) < 30 }.count
        try require(Double(changes.pink) > Double(blackPixels) * 0.75,
                    "A bold coloured source was mistaken for thin handwriting by sampling only its black outline.")
    }
    @MainActor
    private static func checkSolidColourRejection() throws {
        let clean = try colourFixture(colors: [])
        let source = try colourFixture(colors: [])
        let bitmap = source.representations.first as? NSBitmapImageRep
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap!)
        NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 500, height: 320).fill()
        NSGraphicsContext.restoreGraphicsState()
        let block = TextBlock(box: TextBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6), originalText: "BOOM", translatedText: "쾅!",
                              detectedFontSize: 86, textKind: .soundEffect, effectStyleID: "automatic")
        let output = try TranslatedImageRenderer().render(image: clean, blocks: [block], backgroundStyle: .none, originalImage: source)
        let changes = try colourChanges(output: output, clean: clean, box: block.box)
        try require(changes.pink == 0 && changes.blue == 0, "A solid changed background was mistaken for coloured glyphs.")
    }
    @MainActor
    private static func colourChanges(output: NSImage, clean: NSImage, box: TextBox) throws -> (pink: Int, blue: Int, outside: Int, total: Int) {
        let before = try imagePixels(clean), after = try imagePixels(output)
        var pink = 0, blue = 0, outside = 0, total = 0
        for index in after.indices where after[index] != before[index] {
            total += 1
            let x = Double(index % 500) / 500, y = Double(index / 500) / 320
            if x < box.x || x >= box.x + box.width || y < box.y || y >= box.y + box.height { outside += 1 }
            let red = Int((after[index] >> 24) & 255), green = Int((after[index] >> 16) & 255), b = Int((after[index] >> 8) & 255)
            if red > 160 && green < 100 && b > 70 && b < 180 { pink += 1 }
            if red < 100 && green > 35 && green < 160 && b > 160 { blue += 1 }
        }
        return (pink, blue, outside, total)
    }
    @MainActor
    private static func checkColourSizeFailure(in root: URL) throws {
        let cleanURL = root.appendingPathComponent("clean-colour-pink.png"), source = root.appendingPathComponent("source-colour-pink.png")
        let image = NSImage(size: NSSize(width: 10, height: 10)); image.lockFocus(); NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill(); image.unlockFocus()
        let mismatch = root.appendingPathComponent("colour-wrong-size.png"); try saveColourFixture(image, at: mismatch)
        let destination = root.appendingPathComponent("colour-existing-result.png"), sentinel = Data("previous result".utf8)
        try sentinel.write(to: destination)
        let block = TextBlock(box: TextBox(x: 0.1, y: 0.15, width: 0.8, height: 0.7), originalText: "SWISH", translatedText: "휘익",
                              textKind: .soundEffect, effectStyleID: "automatic")
        do {
            _ = try TranslatedImageRenderer().writePNG(sourceImageURL: cleanURL, translation: colourTranslation(block, imageURL: source),
                destinationURL: destination, backgroundStyle: .none, originalImageURL: mismatch)
            try require(false, "Mismatched source dimensions were accepted for colour sampling.")
        } catch TranslatedImageRenderError.originalImageSizeMismatch { }
        try require(try Data(contentsOf: destination) == sentinel, "Colour size failure overwrote an existing result.")
    }

    @MainActor
    private static func checkExplicitBalloonRows(in root: URL) throws {
        let clean = try colourFixture(colors: [])
        let box = TextBox(x: 0.2, y: 0.16, width: 0.66, height: 0.66)
        let block = TextBlock(box: box, originalText: "Please sit down, Mina.", translatedText: "미나 씨,\n여기 앉으세요.",
                              textKind: .dialogue, userDefinedBounds: box)
        let renderer = TranslatedImageRenderer(sourceLanguage: .english)
        let output = try renderer.render(image: clean, blocks: [block], backgroundStyle: .none)
        try saveColourFixture(output, at: root.appendingPathComponent("explicit-balloon-rows.png"))
        let pixels = try imagePixels(output), before = try imagePixels(clean)
        var bands = 0, previousHasInk = false
        for y in 0..<320 {
            var hasInk = false
            for x in 100..<430 where pixels[y * 500 + x] != before[y * 500 + x] { hasInk = true; break }
            if hasInk && !previousHasInk { bands += 1 }
            previousHasInk = hasInk
        }
        try require(bands == 2, "Saved balloon PNG ignored the two explicit dialogue lines.")
    }
}
