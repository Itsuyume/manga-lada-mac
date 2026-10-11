import Foundation
import MangaLadaCore
import MangaLadaImport

/// Whole-book save: names follow the source layout, existing folders are protected, and failure or
/// cancellation leaves neither a partial folder nor a staging folder behind.
@MainActor
enum BookExportChecks {
    static func run(image: URL, root: URL, loader: ComicBookLoader) async throws {
        try checkLayout(root: root)
        let work = root.appendingPathComponent("book-export", isDirectory: true)
        let source = work.appendingPathComponent("원본", isDirectory: true)
        let rendered = work.appendingPathComponent("rendered", isDirectory: true)
        let bytes = try Data(contentsOf: image)
        var sources: [URL] = [], pages: [URL] = []
        for (index, path) in ["1화/001.jpg", "1화/002.jpg", "2화/001.jpg"].enumerated() {
            let page = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: page); sources.append(page)
            let output = rendered.appendingPathComponent(String(format: "%05d.png", index + 1))
            try FileManager.default.createDirectory(at: rendered, withIntermediateDirectories: true)
            try bytes.write(to: output); pages.append(output)
        }
        let layout = try TranslatedBookExporter.layout(rendered: pages, sources: sources)
        try require(layout.map(\.relativePath) == ["1화/001.png", "1화/002.png", "2화/001.png"], "Export did not mirror the source folders: \(layout)")
        let destination = work.appendingPathComponent("원본_한국어", isDirectory: true)
        try await TranslatedBookExporter().export(layout, to: destination)
        for page in layout {
            try require(try Data(contentsOf: destination.appendingPathComponent(page.relativePath)) == bytes, "Exported page changed: \(page.relativePath)")
        }
        try require(try sources.allSatisfy { try Data(contentsOf: $0) == bytes } && pages.allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
                    "Export moved or changed the source or rendered pages.")
        let reopened = try await loader.load(destination)
        try require(reopened.pages.map { $0.url.lastPathComponent } == ["001.png", "002.png", "001.png"], "Exported folder did not reopen in page order.")
        try await checkReplacement(layout: layout, destination: destination, work: work, bytes: bytes)
        try await checkProtection(layout: layout, work: work)
        try await checkCancellation(layout: layout, work: work)
        try require(try leftovers(in: work).isEmpty, "Export left staging folders: \(try leftovers(in: work))")
    }

    private static func checkLayout(root: URL) throws {
        let folder = root.appendingPathComponent("layout")
        func urls(_ names: [String]) -> [URL] { names.map { folder.appendingPathComponent($0) } }
        let single = try TranslatedBookExporter.layout(rendered: urls(["r1"]), sources: urls(["page.webp"]))
        try require(single.map(\.relativePath) == ["page.png"], "A single page lost its name.")
        let clash = try TranslatedBookExporter.layout(rendered: urls(["r1", "r2", "r3"]), sources: urls(["1.jpg", "1.PNG", "2.jpg"]))
        try require(clash.map(\.relativePath) == ["00001_1.png", "00002_1.png", "2.png"], "Colliding names were not separated: \(clash)")
        let shadow = try TranslatedBookExporter.layout(rendered: urls(["r1", "r2"]), sources: urls(["x.jpg", "x.png/1.jpg"]))
        try require(shadow.map(\.relativePath) == ["00001.png", "00002.png"], "A file shadowed a folder: \(shadow)")
        for (rendered, sources) in [([URL](), [URL]()), (urls(["r1"]), urls(["a.jpg", "b.jpg"]))] {
            do { _ = try TranslatedBookExporter.layout(rendered: rendered, sources: sources); throw ImportCheckError.failed("Mismatched export accepted.") }
            catch TranslatedBookExportError.pageMismatch { }
        }
    }

    private static func checkReplacement(layout: [TranslatedBookExporter.Page], destination: URL, work: URL, bytes: Data) async throws {
        // An earlier export of this app (it carries the marker) is replaced as a whole.
        let stale = destination.appendingPathComponent("stale.png"); try bytes.write(to: stale)
        try await TranslatedBookExporter().export(layout, to: destination)
        try require(!FileManager.default.fileExists(atPath: stale.path), "Re-export kept a stale page from the earlier export.")
        try require(FileManager.default.fileExists(atPath: destination.appendingPathComponent(TranslatedBookExporter.marker).path), "Export marker missing.")
    }

    private static func checkProtection(layout: [TranslatedBookExporter.Page], work: URL) async throws {
        let foreign = work.appendingPathComponent("사용자 폴더", isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let note = foreign.appendingPathComponent("memo.txt"); try Data("keep".utf8).write(to: note)
        let file = work.appendingPathComponent("file-target"); try Data("file".utf8).write(to: file)
        for target in [foreign, file] {
            do { try await TranslatedBookExporter().export(layout, to: target); throw ImportCheckError.failed("Export replaced user data at \(target.lastPathComponent).") }
            catch TranslatedBookExportError.occupied { }
        }
        try require(try Data(contentsOf: note) == Data("keep".utf8) && Data(contentsOf: file) == Data("file".utf8), "Refused export changed user data.")
        let empty = work.appendingPathComponent("빈 폴더", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try await TranslatedBookExporter().export(layout, to: empty)
        try require(FileManager.default.fileExists(atPath: empty.appendingPathComponent(layout[0].relativePath).path), "An empty folder was not used.")
        var missing = layout; missing[1] = .init(rendered: work.appendingPathComponent("gone.png"), relativePath: layout[1].relativePath)
        let absent = work.appendingPathComponent("missing-page", isDirectory: true)
        do { try await TranslatedBookExporter().export(missing, to: absent); throw ImportCheckError.failed("Missing page accepted.") }
        catch TranslatedBookExportError.missingPage { }
        try require(!FileManager.default.fileExists(atPath: absent.path), "A failed export created its destination.")
        do { try await TranslatedBookExporter().export(layout, to: work.appendingPathComponent("no-parent/book")); throw ImportCheckError.failed("Missing parent accepted.") }
        catch TranslatedBookExportError.missingParent { }
    }

    private static func checkCancellation(layout: [TranslatedBookExporter.Page], work: URL) async throws {
        let target = work.appendingPathComponent("cancelled", isDirectory: true)
        // The task inherits the main actor, so it cannot start before it is cancelled.
        let task = Task { try await TranslatedBookExporter().export(layout, to: target) }
        task.cancel()
        do { try await task.value; throw ImportCheckError.failed("Cancelled export completed.") } catch is CancellationError { }
        try require(!FileManager.default.fileExists(atPath: target.path), "Cancelled export created its destination.")
    }

    private static func leftovers(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.contains(".partial-") }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw ImportCheckError.failed(message) }
    }
}
