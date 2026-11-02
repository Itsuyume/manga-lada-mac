import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension TranslationStateTests {
    static func checkBookTerminology() throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = BookTerminologyStore(directory: fixture.support.appendingPathComponent("book-terms"))
        let state = AppState(processor: MangaPageProcessor(applicationSupportDirectory: fixture.support),
                             reviewStore: TranslationReviewStore(directory: fixture.support.appendingPathComponent("term-reviews")), terminologyStore: store)
        state.sourceURL = fixture.state.sourceURL; state.pages = fixture.state.pages; state.errorMessage = nil
        let source = try unwrap(state.sourceURL)
        state.loadBookTerminology(for: source)
        check(state.setBookTerm(source: "蒼月", korean: "소게츠"), "Explicit term could not be saved.")
        check(state.bookConfiguration.terminology.entries.first?.korean == "소게츠" && state.configuration.terminology.entries.isEmpty,
              "Per-book request configuration changed global translation settings.")
        let saved = try Data(contentsOf: store.fileURL(for: source))
        state.isBusy = true
        check(!state.setBookTerm(source: "蒼月", korean: "다른이름"), "A term changed while translation was active.")
        state.isBusy = false
        check(try Data(contentsOf: store.fileURL(for: source)) == saved, "Rejected term editing wrote a file.")
        state.loadBookTerminology(for: fixture.root.appendingPathComponent("other.cbz"))
        check(state.bookTerminology.entries.isEmpty, "A different book inherited source terms.")
        state.loadBookTerminology(for: source)
        check(state.bookTerminology.entries.first?.korean == "소게츠", "Reopening a book lost its terms.")
        state.removeBookTerm(source: "蒼月")
        check(try store.load(for: source).entries.isEmpty, "Removing a term did not persist.")
        try Data("damaged".utf8).write(to: store.fileURL(for: source))
        state.loadBookTerminology(for: source)
        check(state.terminologyReadError != nil && !state.requireBookTerminology(), "A damaged term file allowed silent translation without preferences.")
        check(!state.setBookTerm(source: "新", korean: "새이름"), "Editing overwrote an unreadable term file.")
        check(try Data(contentsOf: store.fileURL(for: source)) == Data("damaged".utf8), "The unreadable term file was changed.")
        try store.save(TranslationGlossary(), for: source); state.reloadBookTerminology()
        check(state.terminologyReadError == nil, "Retrying a repaired term file kept a stale read failure.")
        let file = store.fileURL(for: source)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let before = state.bookTerminology
        check(!state.setBookTerm(source: "新", korean: "새이름") && state.bookTerminology == before,
              "Failed term saving published uncommitted in-memory preferences.")
        check(state.results.isEmpty && state.pendingPages.isEmpty && state.reviewDrafts.isEmpty, "Term editing created rendered pages or review drafts.")
        try fixture.checkSources()
        print("PASS book terms: explicit edit/save/reopen/remove, request/global isolation, busy/error recovery and no image/model side effects")
    }
}
