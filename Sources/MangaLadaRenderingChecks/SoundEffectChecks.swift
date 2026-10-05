import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkSoundEffects(in root: URL) throws {
        stage("Registering bundled fonts")
        try SoundEffectFonts.registerBundledFonts()
        try SoundEffectFonts.registerBundledFonts()
        try checkEffectOutlineCoverage()
        stage("Creating sound effect source image")
        let library = try SoundEffectLibrary.standard()
        try require(library.styles.count == 14, "The effect library is incomplete.")
        try require(try library.automaticStyle(original: "ドキドキ", translated: "두근두근").id == "heartbeat", "Heartbeat selection lost its semantic rule.")
        try require(try library.automaticStyle(original: "ドキドキ", translated: "두근두근") == library.automaticStyle(original: "ドキドキ", translated: "두근두근"), "Style selection is not deterministic.")
        let image = NSImage(size: NSSize(width: 500, height: 300))
        image.lockFocus(); NSColor(calibratedWhite: 0.8, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 500, height: 300).fill(); image.unlockFocus()
        let source = image.tiffRepresentation!
        var bytes = Set<Data>()
        for style in library.styles {
            stage("Sound effect \(style.id)")
            let block = TextBlock(box: TextBox(x: 0.14, y: 0.18, width: 0.72, height: 0.64), originalText: "ドーン", translatedText: "쾅!",
                                  detectedFontSize: 94, textKind: .soundEffect, rotationDegrees: 12, effectStyleID: style.id)
            let output = try TranslatedImageRenderer().render(image: image, blocks: [block], backgroundStyle: .none)
            bytes.insert(output.tiffRepresentation!)
            try require(darkPixelBounds(image: output, normalizedArea: CGRect(x: 0.14, y: 0.18, width: 0.72, height: 0.64)) != nil, "Effect glyphs were missing.")
            if style.id == "impact" { try output.tiffRepresentation!.write(to: root.appendingPathComponent("effect-preview.tiff")) }
        }
        try require(bytes.count >= 10, "The effect styles all rendered alike.")
        try checkPunctuationEffects(image: image, library: library, root: root)
        try require(image.tiffRepresentation == source, "Effect rendering altered the source.")
        let oversized = TextBlock(box: TextBox(x: 0.2, y: 0.3, width: 0.1, height: 0.1), originalText: "ドーン",
                                  translatedText: String(repeating: "쾅", count: 500), textKind: .soundEffect)
        do {
            _ = try TranslatedImageRenderer().render(image: image, blocks: [oversized], backgroundStyle: .none)
            try require(false, "Oversized effect text was silently cropped.")
        } catch TranslatedImageRenderError.textDoesNotFit { }
        do {
            _ = try library.style(id: "missing-style")
            try require(false, "An unknown preset was silently substituted.")
        } catch SoundEffectLibraryError.unknownStyle { }
        let legacy = Data(#"{"dialogueFontName":"AppleSDGothicNeo-Bold","effectFontName":"AppleSDGothicNeo-Heavy","fontScale":1}"#.utf8)
        try require(try JSONDecoder().decode(MangaTypography.self, from: legacy).effectStyleID == nil, "Old typography settings no longer decode.")
        print("Sound effect checks passed: 14 presets, Korean glyphs, angle fit, deterministic selection, legacy settings, oversized/unknown errors, unchanged source")
    }

    @MainActor
    private static func checkPunctuationEffects(image: NSImage, library: SoundEffectLibrary, root: URL) throws {
        for (index, pair) in [("…", "..."), ("!?", "!?"), ("ッ", "!")].enumerated() {
            for style in library.styles {
                let block = TextBlock(box: TextBox(x: 0.2, y: 0.25, width: 0.6, height: 0.5), originalText: pair.0,
                                      detectedFontSize: 70, textKind: .soundEffect, effectStyleID: style.id)
                let translated = try MangaNumberedPageResponse.decode("[R0] " + pair.1, blocks: [block])
                let output = try TranslatedImageRenderer().render(image: image, blocks: translated, backgroundStyle: .none)
                try require(darkPixelBounds(image: output, normalizedArea: CGRect(x: 0.2, y: 0.25, width: 0.6, height: 0.5)) != nil,
                            "Punctuation effect was blank for \(style.id): \(pair.1)")
                if style.id == "impact" { try output.tiffRepresentation!.write(to: root.appendingPathComponent("punctuation-\(index).tiff")) }
            }
        }
        print("Punctuation effects passed: response decode through 14 font styles, visible glyphs, source preservation")
    }
}
