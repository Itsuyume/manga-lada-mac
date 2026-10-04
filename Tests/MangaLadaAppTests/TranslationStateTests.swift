import AppKit
import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

@main
@MainActor
struct TranslationStateTests {
    static func main() async throws {
        try await checkFailedPageReview()
        try await checkBlankPageRecovery()
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let state = fixture.state
        check(state.progress == 0 && state.completed.isEmpty, "New book was already complete.")
        state.failures = [0: "First page failed", 1: "Second page failed"]
        state.startTranslation(onlyCurrent: true)
        check(state.failures.count == 2, "Starting a single-page retry discarded other failures.")
        await state.job?.value
        check(state.completed == [0] && state.failures == [1: "Second page failed"], "Subset retry changed untouched pages.")
        check(abs(state.progress - 2.0 / 3.0) < 0.00001, "Subset retry progress lost failed pages.")
        try fixture.checkManifest(completed: [0], failures: [1])
        print("PASS subset retry preserves other failures and manifest")

        state.startTranslation(onlyCurrent: true)
        check(state.job == nil && !state.isBusy, "A completed page without failures was processed again.")
        state.startTranslation()
        state.stop()
        await state.job?.value
        check(state.completed == [0] && state.failures.keys.sorted() == [1], "Cancellation erased outcomes.")
        try fixture.checkManifest(completed: [0], failures: [1])
        print("PASS completed-page skip and cancellation preservation")

        let cleanBefore = try Data(contentsOf: fixture.cleanURL(at: 0))
        let savedBefore = try Data(contentsOf: unwrap(state.results[0]).renderedImageURL)
        let recognitionFile = fixture.cache.cacheFileURL(fingerprint: fixture.keys[0].recognition)
        let recognitionBefore = try Data(contentsOf: recognitionFile)
        try Data("invalid cache".utf8).write(to: recognitionFile, options: .atomic)
        state.startTranslation(onlyCurrent: true, force: true)
        await state.job?.value
        check(state.failures.keys.sorted() == [0, 1] && state.completed.isEmpty, "Failed retranslation was counted as complete.")
        check(abs(state.progress - 2.0 / 3.0) < 0.00001, "Saved and failed page was counted twice.")
        check(try Data(contentsOf: unwrap(state.results[0]).renderedImageURL) == savedBefore, "Failed retry changed previous image.")
        try fixture.checkManifest(completed: [], failures: [0, 1])
        print("PASS failed retranslation preserves image and has no duplicate completion")

        try recognitionBefore.write(to: recognitionFile, options: .atomic)
        state.reviewErrors[0] = "Unreadable draft"
        state.startTranslation()
        check(state.job == nil && !state.isBusy && state.failures.count == 2, "Retry ignored an unapplied review error.")
        state.reviewErrors.removeAll()
        state.startTranslation()
        await state.job?.value
        check(state.completed == [0, 1, 2] && state.failures.isEmpty, "Resume skipped a failed page with an earlier saved image.")
        check(state.progress == 1, "All pages should be processed exactly once.")
        try fixture.checkManifest(completed: [0, 1, 2], failures: [])
        check(try Data(contentsOf: fixture.cleanURL(at: 0)) == cleanBefore, "Retry changed source clean image.")
        print("PASS review protection and resume of failed saved page")

        state.configuration.provider = .ollama
        state.configuration.ollama.model = ""
        state.failures = [1: "Keep this failure"]
        state.startTranslation(onlyCurrent: true, force: true)
        await state.job?.value
        check(state.failures == [1: "Keep this failure"] && !state.isBusy, "Model setup failure erased unrelated failures.")
        check(state.errorMessage != nil, "Model setup failure was hidden.")
        check(state.progress == 1 && state.completed == [0, 2], "Setup failure produced invalid completion/progress.")
        state.pages = []; state.results = [:]; state.failures = [:]
        check(state.progress == 0, "Empty book progress is invalid.")
        try fixture.checkSources()
        print("PASS setup failure, empty book, source and preference preservation")
        print("Translation state checks passed; real app/workflow, no model requests")
    }

    static func check(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError(message, file: file, line: line) }
    }
    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure.missingValue }
        return value
    }
    enum Failure: Error { case missingValue }

    @MainActor
    struct Fixture {
        let root: URL
        let support: URL
        let state: AppState
        let cache: TranslationCache
        let keys: [JapanesePageKeys]
        let sources: [(URL, Data)]
        let preferences: [String: Any]

        init(blocks: [TextBlock] = []) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("manga-state-" + UUID().uuidString)
            support = root.appendingPathComponent("support")
            let sourceFolder = root.appendingPathComponent("source")
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            preferences = Self.readingPreferences()
            state = AppState(processor: MangaPageProcessor(applicationSupportDirectory: support),
                             reviewStore: TranslationReviewStore(directory: support.appendingPathComponent("reviews")))
            // Empty cached recognition exercises real workflow without OCR/model downloads.
            // Gemini has no key here, so an unexpected model request fails before networking.
            state.configuration = LocalTranslatorConfiguration(provider: .geminiFlashLite, enhanceSoundEffects: false)
            state.configuration.gemini.apiKey = ""
            state.typography = MangaTypography()
            state.outputRoot = root.appendingPathComponent("output")
            state.sourceURL = sourceFolder
            state.title = "Neutral retry checks"
            state.errorMessage = nil
            cache = TranslationCache(cacheDirectory: support.appendingPathComponent("Cache"))
            let engine = BallonsTranslatorEngine.standard(applicationSupportDirectory: support)
            var records: [(URL, Data)] = [], pageKeys: [JapanesePageKeys] = []
            for index in 0..<3 {
                let image = sourceFolder.appendingPathComponent("\(index).png")
                let width = blocks.isEmpty ? 2 : 480, height = blocks.isEmpty ? 2 : 640
                let bitmap = try unwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32))
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSColor(deviceWhite: 1 - Double(index) * 0.1, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: width, height: height).fill()
                NSGraphicsContext.restoreGraphicsState()
                let bytes = try unwrap(bitmap.representation(using: .png, properties: [:]))
                try bytes.write(to: image)
                records.append((image, bytes))
                let key = try JapanesePageKeys(imageURL: image, configuration: state.configuration, context: "", title: state.title)
                pageKeys.append(key)
                for fingerprint in [key.translation, key.recognition] {
                    if !blocks.isEmpty && fingerprint == key.translation { continue }
                    try cache.save(PageTranslation(imageURL: image, imageFingerprint: fingerprint,
                        sourceLanguage: .japanese, targetLanguage: .korean, blocks: blocks))
                }
                let clean = engine.inpaintedImageURL(runID: key.recognition)
                try FileManager.default.createDirectory(at: clean.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: clean)
                state.pages.append(ImagePage(url: image))
            }
            sources = records; keys = pageKeys
        }
        func cleanURL(at index: Int) -> URL {
            BallonsTranslatorEngine.standard(applicationSupportDirectory: support).inpaintedImageURL(runID: keys[index].recognition)
        }
        func checkManifest(completed: [Int], failures: [Int]) throws {
            let book = try unwrap(state.outputBook)
            let url = book.directory.appendingPathComponent(ImageFileScanner.generatedBookMarker)
            let manifest = try JSONDecoder().decode(TranslationBookManifest.self, from: Data(contentsOf: url))
            check(manifest.completedPages == completed && manifest.failures.keys.sorted() == failures, "Saved manifest disagrees with page status.")
        }
        func checkSources() throws {
            for (url, bytes) in sources { check(try Data(contentsOf: url) == bytes, "Source image changed.") }
            check(NSDictionary(dictionary: Self.readingPreferences()).isEqual(to: preferences), "App preferences changed.")
        }
        private static func readingPreferences() -> [String: Any] {
            UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("translator.") || $0.key.hasPrefix("reader.") }
        }
    }
}
