import AppKit
import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

@MainActor
enum LegacyPunctuationCacheChecks {
    private static let bookTitle = "Legacy punctuation"
    private struct Scenario {
        let name: String
        let saved: [TextBlock]
        let recognized: [TextBlock]?
        var copiesSource = false
        var expectedMarker: Bool?
        var corruptRecognition = false
        var expectsReadFailure = false
        var translationCacheExists = true
    }

    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyPunctuationCacheChecks/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.png"), clean = root.appendingPathComponent("clean.png")
        for (url, cleaned) in [(source, false), (clean, true)] {
            let bitmap = NSBitmapImageRep(data: PunctuationReviewChecks.image(cleaned: cleaned).tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        }
        let sourceBytes = try Data(contentsOf: source), cleanBytes = try Data(contentsOf: clean)
        let original = TextBlock(box: .init(x: 0.3, y: 0.3, width: 0.4, height: 0.4), originalText: "・",
                                 translatedText: "・", detectedFontSize: 28)
        var edited = original; edited.originalText = "!"; edited.translatedText = "!"
        var moved = original; moved.box.x += 0.01
        var other = original; other.id = UUID()
        var recorded = edited; recorded.userDefinedOriginalText = true
        var verified = original; verified.userDefinedOriginalText = false
        var word = original; word.originalText = "音"; word.translatedText = "소리"
        var placed = original; placed.userDefinedBounds = original.box
        var classified = original; classified.userDefinedTextKind = true
        var styled = original; styled.effectStyleID = "impact"
        var translated = original; translated.translatedText = "!"
        let scenarios = [
            Scenario(name: "edited-legacy", saved: [edited], recognized: [original], expectedMarker: true),
            Scenario(name: "original-legacy", saved: [original], recognized: [original], copiesSource: true, expectedMarker: false),
            Scenario(name: "missing-record", saved: [edited], recognized: nil),
            Scenario(name: "missing-region", saved: [edited], recognized: []),
            Scenario(name: "different-region", saved: [edited], recognized: [other]),
            Scenario(name: "moved-region", saved: [edited], recognized: [moved]),
            Scenario(name: "duplicate-region", saved: [edited], recognized: [original, original]),
            Scenario(name: "recorded-edit", saved: [recorded], recognized: nil, expectedMarker: true, corruptRecognition: true),
            Scenario(name: "verified-source", saved: [verified], recognized: nil, copiesSource: true, expectedMarker: false, corruptRecognition: true),
            Scenario(name: "word-no-read", saved: [word], recognized: nil, corruptRecognition: true),
            Scenario(name: "manual-placement-no-read", saved: [placed], recognized: nil, corruptRecognition: true),
            Scenario(name: "manual-kind-no-read", saved: [classified], recognized: nil, corruptRecognition: true),
            Scenario(name: "manual-style-no-read", saved: [styled], recognized: nil, corruptRecognition: true),
            Scenario(name: "changed-translation-no-read", saved: [translated], recognized: nil, corruptRecognition: true),
            Scenario(name: "empty-no-read", saved: [], recognized: nil, corruptRecognition: true),
            Scenario(name: "required-corrupt-record", saved: [edited], recognized: nil, corruptRecognition: true, expectsReadFailure: true),
            Scenario(name: "first-translation", saved: [original], recognized: [original], copiesSource: true,
                     expectedMarker: false, translationCacheExists: false)
        ]
        for scenario in scenarios {
            try await check(scenario, support: root.appendingPathComponent(scenario.name), source: source, clean: clean)
        }
        try require(Data(contentsOf: source) == sourceBytes && Data(contentsOf: clean) == cleanBytes, "Legacy verification changed source images.")
        print("Legacy punctuation cache passed: \(scenarios.count) saved-page cases, real process path, source/translation/placement retention, conditional OCR reads and no cache rewrites; \(root.path)")
    }

    private static func check(_ scenario: Scenario, support: URL, source: URL, clean: URL) async throws {
        let configuration = LocalTranslatorConfiguration(enhanceSoundEffects: false)
        let keys = try JapanesePageKeys(imageURL: source, configuration: configuration, context: "", title: bookTitle)
        let cache = TranslationCache(cacheDirectory: support.appendingPathComponent("Cache"))
        let saved = PageTranslation(imageURL: source, imageFingerprint: keys.translation,
                                     sourceLanguage: .japanese, targetLanguage: .korean, blocks: scenario.saved)
        if scenario.translationCacheExists { try cache.save(saved) }
        let recognitionURL = cache.cacheFileURL(fingerprint: keys.recognition)
        if scenario.corruptRecognition { try Data("broken OCR JSON".utf8).write(to: recognitionURL) }
        else if let blocks = scenario.recognized {
            var recognized = saved; recognized.imageFingerprint = keys.recognition; recognized.blocks = blocks
            try cache.save(recognized)
        }
        let cachedBytes = try scenario.translationCacheExists ? Data(contentsOf: cache.cacheFileURL(fingerprint: keys.translation)) : nil
        let recognitionBytes = try FileManager.default.fileExists(atPath: recognitionURL.path) ? Data(contentsOf: recognitionURL) : nil
        let cleanURL = BallonsTranslatorEngine.standard(applicationSupportDirectory: support).inpaintedImageURL(runID: keys.recognition)
        try FileManager.default.createDirectory(at: cleanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: clean).write(to: cleanURL)
        let output = support.appendingPathComponent("output.png"), existing = Data("existing output".utf8)
        try existing.write(to: output)
        do {
            let processed = try await MangaPageProcessor(applicationSupportDirectory: support).process(
                imageURL: source, destinationURL: output, configuration: configuration, typography: MangaTypography(), bookTitle: bookTitle)
            try require(!scenario.expectsReadFailure, "\(scenario.name): malformed required OCR cache was ignored.")
            try require(processed.wasCached == scenario.translationCacheExists, "\(scenario.name): wrong cache path.")
            let renderer = TranslatedImageRenderer()
            let reference = try renderer.render(image: NSImage(contentsOf: scenario.copiesSource ? source : clean)!,
                                                blocks: scenario.copiesSource ? [] : scenario.saved, backgroundStyle: .none)
            let actual = try renderer.render(image: NSImage(contentsOf: output)!, blocks: [])
            try require(actual.tiffRepresentation == reference.tiffRepresentation,
                        "\(scenario.name): saved punctuation was replaced with the wrong source artwork.")
            for (index, block) in processed.translation.blocks.enumerated() {
                var expected = scenario.saved[index]; expected.userDefinedOriginalText = scenario.expectedMarker
                try require(block == expected, "\(scenario.name): verification changed reviewed text/geometry/style or lost its provenance.")
            }
        } catch is DecodingError {
            try require(scenario.expectsReadFailure && Data(contentsOf: output) == existing,
                        "\(scenario.name): irrelevant OCR error or overwritten prior output.")
        }
        if let cachedBytes {
            try require(Data(contentsOf: cache.cacheFileURL(fingerprint: keys.translation)) == cachedBytes,
                        "\(scenario.name): loading a legacy page rewrote its translation cache.")
        } else {
            try require(cache.load(fingerprint: keys.translation)?.blocks.first?.userDefinedOriginalText == false,
                        "\(scenario.name): first translation did not store verified punctuation provenance.")
        }
        if let recognitionBytes {
            try require(Data(contentsOf: recognitionURL) == recognitionBytes, "\(scenario.name): verification changed the OCR cache.")
        } else {
            try require(!FileManager.default.fileExists(atPath: recognitionURL.path), "\(scenario.name): verification created an OCR cache.")
        }
    }

    private static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw CheckError.failed(message) }
    }
    private enum CheckError: Error { case failed(String) }
}
