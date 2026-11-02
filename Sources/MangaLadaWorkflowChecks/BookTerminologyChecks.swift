import Foundation
import MangaLadaCore
import MangaLadaWorkflow

enum BookTerminologyChecks {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("book-terms-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BookTerminologyStore(directory: root.appendingPathComponent("terms"))
        let book = root.appendingPathComponent("first.cbz"), other = root.appendingPathComponent("second.cbz")
        let source = Data("unchanged source bytes".utf8); try source.write(to: book)
        let glossary = try TranslationGlossary().setting(source: "蒼月", korean: "소게츠")
        try check(try store.load(for: book).entries.isEmpty, "An unopened book already had terms.")
        try store.save(glossary, for: book)
        try check(try store.load(for: book) == glossary && store.load(for: other).entries.isEmpty, "Book terms leaked across source identities.")
        let file = store.fileURL(for: book)
        try Data("damaged glossary".utf8).write(to: file)
        do { _ = try store.load(for: book); throw Failure.failed("A damaged glossary was hidden.") }
        catch is DecodingError { }
        try check(try Data(contentsOf: file) == Data("damaged glossary".utf8), "Loading damaged terms modified the saved file.")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let note = file.appendingPathComponent("keep"); try source.write(to: note)
        do { try store.save(glossary, for: book); throw Failure.failed("A directory was replaced with glossary data.") }
        catch { if error is Failure { throw error } }
        try check(try Data(contentsOf: note) == source && Data(contentsOf: book) == source, "Failed term storage modified source or unrelated files.")
        print("Book terminology storage passed: per-book isolation, reload, damaged-file preservation and failed-save side effects")
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.failed(message) } }
    private enum Failure: Error { case failed(String) }
}
