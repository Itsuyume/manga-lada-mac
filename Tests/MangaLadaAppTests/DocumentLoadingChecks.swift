import CoreGraphics
import Foundation
import MangaLadaCore
import MangaLadaImport
import MangaLadaWorkflow

extension TranslationStateTests {
    static func checkDocumentLoading() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let cache = fixture.root.appendingPathComponent("document-cache")
        let state = AppState(processor: MangaPageProcessor(applicationSupportDirectory: fixture.support),
                             reviewStore: TranslationReviewStore(directory: fixture.support.appendingPathComponent("document-reviews")),
                             loader: ComicBookLoader(extractionRoot: cache))
        state.pages = fixture.state.pages; state.title = "Previous book"; state.errorMessage = nil
        let source = fixture.root.appendingPathComponent("loading.pdf")
        var rect = CGRect(x: 0, y: 0, width: 100, height: 150)
        let consumer = try unwrap(CGDataConsumer(url: source as CFURL))
        let context = try unwrap(CGContext(consumer: consumer, mediaBox: &rect, nil))
        for _ in 0..<80 { context.beginPDFPage(nil); context.endPDFPage() }; context.closePDF()
        let original = try Data(contentsOf: source)
        let opening = Task { await state.open(source) }
        let monitor = Task.detached {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: cache.path) {
                    let folders = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
                    if folders.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("00001.png").path) }) {
                        await MainActor.run { state.stop() }; return
                    }
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            await MainActor.run { state.stop() }
            throw Failure.missingValue
        }
        await opening.value; try await monitor.value
        check(!state.isLoading && state.documentLoad == nil && !state.isBusy, "Stopping document loading left an active task or loading state.")
        check(state.pages == fixture.state.pages && state.title == "Previous book", "Stopping a document load replaced the previous book.")
        check(state.errorMessage == nil && state.statusMessage.contains("중단"), "Document cancellation appeared as a file error.")
        check(try Data(contentsOf: source) == original, "Document cancellation modified the source PDF.")
        let cancelled = Task { await state.open(source) }; cancelled.cancel(); await cancelled.value
        check(!state.isLoading && state.documentLoad == nil && state.pages == fixture.state.pages,
              "Cancelling the caller did not cancel its document load.")
        try fixture.checkSources()
        print("PASS document stop/caller cancellation preserves the previous book, source, preferences and task lifecycle")
    }
}
