import AppKit
import Foundation
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

@MainActor
enum PunctuationReviewChecks {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PunctuationReviewChecks/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.tiff"), clean = root.appendingPathComponent("clean.tiff")
        let destination = root.appendingPathComponent("output.png")
        try image(cleaned: false).tiffRepresentation!.write(to: source)
        try image(cleaned: true).tiffRepresentation!.write(to: clean)
        let sourceData = try Data(contentsOf: source), cleanData = try Data(contentsOf: clean)
        let block = TextBlock(box: .init(x: 0.3, y: 0.3, width: 0.4, height: 0.4), originalText: "・",
                              translatedText: "・", detectedFontSize: 28, userDefinedOriginalText: false)
        let page = PageTranslation(imageURL: source, imageFingerprint: "review", sourceLanguage: .japanese,
                                   targetLanguage: .korean, blocks: [block])
        var result = try PageImageRendering.render(translation: page, cleanImageURL: clean,
                                                   destinationURL: destination, typography: MangaTypography(), wasCached: false)
        var primary = page; primary.imageFingerprint = "primary"
        result.primaryTranslation = primary
        let originalOutput = try Data(contentsOf: destination)
        var oldPage = page; oldPage.blocks[0].userDefinedOriginalText = nil
        let oldJSON = try JSONEncoder().encode(oldPage)
        let legacy = try JSONDecoder().decode(PageTranslation.self, from: oldJSON)
        try require(legacy.blocks[0].userDefinedOriginalText == nil, "Legacy blocks acquired a user-edit marker.")
        var edits = page
        edits.blocks[0].originalText = "!"; edits.blocks[0].translatedText = "!"
        let processor = MangaPageProcessor(applicationSupportDirectory: root)
        let applied = try processor.applyEdits(to: result, translation: edits, typography: MangaTypography())
        try require(applied.translation.blocks[0].userDefinedOriginalText == true, "Applying a corrected source did not preserve its edit marker.")
        let editedOutput = try Data(contentsOf: destination)
        let reference = root.appendingPathComponent("reference.png")
        _ = try TranslatedImageRenderer().writePNG(sourceImageURL: clean, translation: edits, destinationURL: reference, backgroundStyle: .none)
        try require(editedOutput == Data(contentsOf: reference) && editedOutput != originalOutput, "Corrected punctuation restored the old glyph instead of typesetting the edit.")
        let cache = TranslationCache(cacheDirectory: root.appendingPathComponent("Cache"))
        let stored = try cache.load(fingerprint: "review")!
        try require(stored.blocks == applied.translation.blocks && cache.load(fingerprint: "primary")?.blocks == stored.blocks,
                    "Review or primary cache lost corrected source metadata.")
        let reopenedURL = root.appendingPathComponent("reopened.png")
        _ = try PageImageRendering.render(translation: stored, cleanImageURL: clean, destinationURL: reopenedURL,
                                          typography: MangaTypography(), wasCached: true)
        try require(Data(contentsOf: reopenedURL) == editedOutput, "Reopening a saved review replaced the corrected glyph.")
        try require(Data(contentsOf: source) == sourceData && Data(contentsOf: clean) == cleanData && page.blocks == [block],
                    "Applying punctuation edits changed original images or baseline data.")
        print("Punctuation review passed: corrected source and translation, legacy decoding, primary cache, reopen and source preservation")
    }

    static func image(cleaned: Bool) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 200, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 200, height: 200).fill()
        if !cleaned { NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 80, y: 80, width: 40, height: 40)).fill() }
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: NSSize(width: 200, height: 200)); result.addRepresentation(bitmap)
        return result
    }

    private static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw CheckError.failed(message) }
    }
    private enum CheckError: Error { case failed(String) }
}
