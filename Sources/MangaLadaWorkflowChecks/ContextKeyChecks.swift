import AppKit
import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

/// A reviewed page keeps its applied edits when the previous page's text (and so the context key)
/// changes. The provider has no API key, so any model call would fail the check.
@MainActor
enum ContextKeyChecks {
    private static let bookTitle = "Context key"

    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ContextKeyChecks/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support")
        let source = root.appendingPathComponent("source.png"), clean = root.appendingPathComponent("clean.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (url, cleaned) in [(source, false), (clean, true)] {
            let bitmap = NSBitmapImageRep(data: PunctuationReviewChecks.image(cleaned: cleaned).tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        let configuration = LocalTranslatorConfiguration(provider: .geminiFlashLite)
        try require(configuration.usesPreviousPageContext && configuration.gemini.apiKey.isEmpty, "Fixture must key on context and fail any model call.")
        let first = "前のページ: 前の訳", edited = "前のページ: 고친 번역"
        let keys = try JapanesePageKeys(imageURL: source, configuration: configuration, context: first, title: bookTitle)
        let other = try JapanesePageKeys(imageURL: source, configuration: configuration, context: edited, title: bookTitle)
        try require(keys.translation != other.translation && keys.latest == other.latest, "Fixture contexts did not change only the context key.")
        let cache = TranslationCache(cacheDirectory: support.appendingPathComponent("Cache"))
        let word = TextBlock(box: .init(x: 0.3, y: 0.3, width: 0.4, height: 0.4), originalText: "音", translatedText: "소리", detectedFontSize: 28)
        var recognized = PageTranslation(imageURL: source, imageFingerprint: keys.recognition, sourceLanguage: .japanese, targetLanguage: .korean,
                                         blocks: [word])
        recognized.blocks[0].translatedText = ""
        try cache.save(recognized)
        var reviewed = recognized; reviewed.imageFingerprint = keys.translation
        reviewed.blocks[0].translatedText = "소리!"; reviewed.blocks[0].fontScale = 0.9
        try cache.save(reviewed)
        let cleanURL = BallonsTranslatorEngine.standard(applicationSupportDirectory: support).inpaintedImageURL(runID: keys.recognition)
        try FileManager.default.createDirectory(at: cleanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: clean).write(to: cleanURL)
        let processor = MangaPageProcessor(applicationSupportDirectory: support)
        let output = root.appendingPathComponent("page.png")
        let opened = try await processor.process(imageURL: source, destinationURL: output, configuration: configuration,
                                                 typography: MangaTypography(), previousContext: first, bookTitle: bookTitle)
        try require(opened.wasCached && opened.translation.blocks == reviewed.blocks, "The reviewed page did not open from its cache.")
        let reopened = try await processor.process(imageURL: source, destinationURL: output, configuration: configuration,
                                                   typography: MangaTypography(), previousContext: edited, bookTitle: bookTitle)
        try require(reopened.translation.blocks.map(\.translatedText) == ["소리!"] && reopened.translation.blocks[0].fontScale == 0.9,
                    "Editing the previous page discarded this page's applied review.")
        try require(try cache.load(fingerprint: other.translation)?.blocks == reopened.translation.blocks
                    && cache.load(fingerprint: keys.translation)?.blocks == reviewed.blocks, // createdAt is stored at ISO-8601 precision.
                    "Reuse did not store the page under its new key or changed the old entry.")
        try require(cache.pointerTarget(keys.latest) == other.translation, "The latest pointer did not follow the newest translation.")
        try Data("../outside".utf8).write(to: cache.cacheFileURL(fingerprint: keys.latest).deletingPathExtension().appendingPathExtension("pointer"))
        try require(cache.pointerTarget(keys.latest) == nil && (try cache.loadPointer(keys.latest)) == nil, "An invalid pointer was followed.")
        do { try cache.savePointer("bad/name", to: keys.translation); throw CheckError.failed("An unsafe pointer name was written.") }
        catch TranslationCacheError.invalidPointer { }
        print("Context key checks passed: reviewed page reused after the previous page changed, no model call, pointer validation")
    }

    private static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw CheckError.failed(message) }
    }
    private enum CheckError: Error { case failed(String) }
}
