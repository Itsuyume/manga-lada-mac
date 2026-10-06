import CoreGraphics
import Foundation
import ImageIO
import MangaLadaCore
import MangaLadaImport
import MangaLadaWorkflow
import UniformTypeIdentifiers

@main
struct MangaLadaImportChecks {
    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == "--export" {
            guard arguments.count == 4 else { throw ImportCheckError.failed("Usage: MangaLadaImportChecks --export <completed-folder> <output.cbz>") }
            try await exportBook(source: URL(fileURLWithPath: arguments[2]), destination: URL(fileURLWithPath: arguments[3]))
            return
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("comic-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("book.with.dots")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in ["1.png", "2.png", "10.png"] { try writeImage(to: source.appendingPathComponent(name)) }
        let loader = ComicBookLoader(extractionRoot: root.appendingPathComponent("cache"))
        let book = try await loader.load(source)
        try check(book.pages.map(\.url.lastPathComponent) == ["1.png", "2.png", "10.png"] && book.title == "book.with.dots", "Folder order or title is wrong.")
        let imageBook = try await loader.load(source.appendingPathComponent("2.png"))
        try check(imageBook.initialIndex == 1 && imageBook.sourceURL.standardizedFileURL.path == source.standardizedFileURL.path, "Opening an image did not select its page in the same book.")
        try await ImageInputChecks.run(image: source.appendingPathComponent("2.png"), root: root, loader: loader)
        try ReadingGestureChecks.run()
        try await checkArchives(source: source, root: root, loader: loader)
        try await checkConcurrentArchive(source: source, root: root)
        try await checkPDF(root: root, loader: loader)
        let exported = root.appendingPathComponent("export.cbz")
        try await checkCBZExport(book: book, destination: exported, loader: loader)
        try checkBookOutput(source: source, book: book, root: root)
        if let path = CommandLine.arguments.dropFirst().first { try checkRAR(URL(fileURLWithPath: path), root: root) }
        print("MangaLadaImportChecks passed: folders, natural order, ZIP/CBZ, 7z/CB7, TAR, PDF, CBZ export, output isolation")
    }
    private static func exportBook(source: URL, destination: URL) async throws {
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("comic-round-trip-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cache) }
        let loader = ComicBookLoader(extractionRoot: cache)
        let book = try await loader.load(source)
        try await checkCBZExport(book: book, destination: destination, loader: loader)
        print("CBZ export checks passed: \(book.pages.count) pages, every page restored byte-for-byte, source preserved")
    }
    private static func checkCBZExport(book: ComicBook, destination: URL, loader: ComicBookLoader) async throws {
        let fingerprint = ImageFingerprint()
        let expected = try book.pages.map { try fingerprint.make(for: $0.url) }
        try await CBZExporter().export(pages: book.pages.map(\.url), to: destination)
        let roundTrip = try await loader.load(destination)
        try check(roundTrip.pages.count == book.pages.count, "CBZ round trip changed the page count.")
        for index in book.pages.indices {
            try check(try fingerprint.make(for: roundTrip.pages[index].url) == expected[index], "CBZ round trip changed page \(index + 1).")
            try check(try fingerprint.make(for: book.pages[index].url) == expected[index], "CBZ export changed source page \(index + 1).")
        }
    }
    private static func checkArchives(source: URL, root: URL, loader: ComicBookLoader) async throws {
        for (suffix, format) in [("zip", "zip"), ("cbz", "zip"), ("7z", "7zip"), ("cb7", "7zip"), ("tar", "pax")] {
            let archive = root.appendingPathComponent("sample." + suffix)
            try command(["--format=" + format, "-cf", archive.path, "-C", source.path, "."])
            let bytes = try Data(contentsOf: archive)
            let first = try await loader.load(archive), second = try await loader.load(archive)
            try check(first.pages.count == 3 && first.pages == second.pages, "Archive import/cache failed for \(suffix).")
            try check(try Data(contentsOf: archive) == bytes, "Archive input was modified.")
        }
        let broken = root.appendingPathComponent("broken.7z"); try Data("broken".utf8).write(to: broken)
        do { _ = try await loader.load(broken); throw ImportCheckError.failed("Corrupt archive was accepted.") }
        catch ArchiveExtractionError.extractionFailed { }
        let empty = root.appendingPathComponent("empty"); try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        do { _ = try await loader.load(empty); throw ImportCheckError.failed("Empty folder was accepted.") }
        catch ComicImportError.emptyBook { }
    }
    private static func checkPDF(root: URL, loader: ComicBookLoader) async throws {
        let pdf = root.appendingPathComponent("pages.pdf")
        guard let consumer = CGDataConsumer(url: pdf as CFURL), let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw ImportCheckError.failed("Cannot make PDF fixture.") }
        for _ in 0..<2 { context.beginPDFPage(nil); context.endPDFPage() }; context.closePDF()
        let book = try await loader.load(pdf)
        try check(book.pages.count == 2 && book.pages.allSatisfy { CGImageSourceCreateWithURL($0.url as CFURL, nil) != nil }, "PDF pages did not render.")
        let rendered = try FileManager.default.contentsOfDirectory(atPath: book.pages[0].url.deletingLastPathComponent().path)
        try check(rendered.sorted() == ["00001.png", "00002.png"], "PDF rendering left partial or extra page files.")
        let fingerprint = ImageFingerprint()
        try check(try fingerprint.make(for: pdf) == fingerprint.make(for: Data(contentsOf: pdf)), "Streaming and in-memory fingerprints differ.")
    }
    private static func checkConcurrentArchive(source: URL, root: URL) async throws {
        let archive = root.appendingPathComponent("concurrent.cbz")
        try command(["--format=zip", "-cf", archive.path, "-C", source.path, "."])
        let cache = root.appendingPathComponent("concurrent-cache")
        let firstLoader = ComicBookLoader(extractionRoot: cache), secondLoader = ComicBookLoader(extractionRoot: cache)
        async let first = firstLoader.load(archive)
        async let second = secondLoader.load(archive)
        let books = try await (first, second)
        try check(books.0.pages == books.1.pages && books.0.pages.count == 3, "Concurrent imports damaged shared cache.")
        try check(books.0.pages.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) }, "Concurrent extraction removed live pages.")
    }
    private static func checkRAR(_ source: URL, root: URL) throws {
        let bytes = try Data(contentsOf: source)
        let extractor = ArchiveExtractor(extractionRoot: root.appendingPathComponent("rar-cache"))
        let archive = root.appendingPathComponent("fixture.cbr"); try bytes.write(to: archive)
        let rar = try extractor.extract(source), cbr = try extractor.extract(archive)
        try check(rar == cbr && rar == (try extractor.extract(source)), "RAR/CBR cache did not reuse identical contents.")
        let files = try FileManager.default.contentsOfDirectory(at: rar, includingPropertiesForKeys: nil).filter { !$0.lastPathComponent.hasPrefix(".") }
        try check(!files.isEmpty && files.allSatisfy { (try? Data(contentsOf: $0).isEmpty) == false }, "RAR pages/files were not extracted.")
        try check(try Data(contentsOf: source) == bytes, "RAR input was changed.")
        print("RAR/CBR extraction checks passed")
    }
    private static func checkBookOutput(source: URL, book: ComicBook, root: URL) throws {
        let store = TranslationBookStore()
        let outputRoot = source.appendingPathComponent("finished")
        let first = try store.prepare(sourceURL: source, title: book.title, pages: book.pages, outputRoot: outputRoot)
        try writeImage(to: first.pageURL(at: 0))
        let second = try store.prepare(sourceURL: source, title: book.title, pages: book.pages, outputRoot: outputRoot)
        try check(first.directory == second.directory, "Resume created a duplicate output book.")
        try check(try ImageFileScanner().images(in: source, recursive: true).count == 3, "Generated output inside input folder was imported as an original.")
        let reserved = root.appendingPathComponent("private_한국어"); try FileManager.default.createDirectory(at: reserved, withIntermediateDirectories: true)
        let note = reserved.appendingPathComponent("note.txt"); try Data("keep".utf8).write(to: note)
        let isolated = try store.prepare(sourceURL: source, title: "private", pages: book.pages, outputRoot: root)
        try check(isolated.directory != reserved && (try String(contentsOf: note, encoding: .utf8)) == "keep", "Unrelated output folder was overwritten.")
    }
    private static func writeImage(to url: URL) throws {
        let context = CGContext(data: nil, width: 8, height: 12, bitsPerComponent: 8, bytesPerRow: 32,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 8, height: 12))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        try check(CGImageDestinationFinalize(destination), "Fixture PNG failed.")
    }
    private static func command(_ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar"); process.arguments = arguments
        try process.run(); process.waitUntilExit(); try check(process.terminationStatus == 0, "Cannot create archive fixture.")
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw ImportCheckError.failed(message) } }
}
private enum ImportCheckError: Error { case failed(String) }
