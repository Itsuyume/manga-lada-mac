import AppKit
import Foundation
import MangaLadaCore
import MangaLadaImport
import MangaLadaViewerUI

@MainActor
enum ImageInputChecks {
    static func run(image: URL, root: URL, loader: ComicBookLoader) async throws {
        let bytes = try Data(contentsOf: image)
        let exported = root.appendingPathComponent("uuid=test&library=1.png")
        try bytes.write(to: exported)
        let snapshot = try await loader.load(.externalFile(exported))
        try require(snapshot.pages.count == 1 && snapshot.pages[0].url != exported, "External image scanned its parent or kept a temporary URL.")
        try FileManager.default.removeItem(at: exported)
        try require(try Data(contentsOf: snapshot.pages[0].url) == bytes, "Deleting the external temporary file damaged the imported image.")
        let duplicate = try await loader.load(.image(bytes))
        try require(duplicate.pages == snapshot.pages, "Identical copied images accumulated duplicate storage.")
        for invalid in [Data(), Data("not an image".utf8)] {
            do { _ = try await loader.load(.image(invalid)); throw ImageInputFailure.failed("Invalid image was accepted.") }
            catch ComicImportError.invalidImage { }
        }
        do { _ = try await loader.load(.externalFile(exported)); throw ImageInputFailure.failed("Moved image was silently ignored.") }
        catch let error as CocoaError { try require(error.code == .fileReadNoSuchFile, "Wrong missing-file error.") }
        try checkPasteboard(bytes: bytes, image: image, loader: loader)
        print("Image input checks passed: isolated external image, temporary-file removal, deduplication, invalid/missing input, actual image/file/text pasteboard")
    }
    private static func checkPasteboard(bytes: Data, image: URL, loader: ComicBookLoader) throws {
        let board = NSPasteboard(name: .init("manga-check-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        board.clearContents()
        try require(!ComicImagePaste.hasImage(in: board), "Empty clipboard stole text-editor paste.")
        do { _ = try ComicImagePaste.input(from: board); throw ImageInputFailure.failed("Empty clipboard was accepted.") }
        catch ComicPasteError.noImage { }
        board.setString("plain text", forType: .string)
        try require(!ComicImagePaste.hasImage(in: board), "Plain text stole text-editor paste.")
        do { _ = try ComicImagePaste.input(from: board); throw ImageInputFailure.failed("Plain text became an image path.") }
        catch ComicPasteError.noImage { }
        board.clearContents(); board.setData(bytes, forType: .png)
        try require(ComicImagePaste.hasImage(in: board), "Copied pixels were missed while editing text.")
        guard case .image(let pasted) = try ComicImagePaste.input(from: board), pasted == bytes else { throw ImageInputFailure.failed("Image clipboard data changed.") }
        board.clearContents(); board.writeObjects([image as NSURL])
        try require(ComicImagePaste.hasImage(in: board), "Copied image file URL was missed while editing text.")
        guard case .externalFile(let url) = try ComicImagePaste.input(from: board), url.standardizedFileURL == image.standardizedFileURL else {
            throw ImageInputFailure.failed("File clipboard URL was lost.")
        }
        try require(try Data(contentsOf: image) == bytes, "Pasteboard checks modified the source image.")
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ImageInputFailure.failed(message) }
    }
}
private enum ImageInputFailure: Error { case failed(String) }
