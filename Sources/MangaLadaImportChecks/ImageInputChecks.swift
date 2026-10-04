import AppKit
import Foundation
import MangaLadaCore
import MangaLadaImport
import MangaLadaViewerUI

@MainActor
enum ImageInputChecks {
    static func run(image: URL, root: URL, loader: ComicBookLoader) async throws {
        try await checkSelectedFolder(image: image, root: root, loader: loader)
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
    private static func checkSelectedFolder(image: URL, root: URL, loader: ComicBookLoader) async throws {
        let folder = image.deletingLastPathComponent()
        let original = try ImageFileScanner().images(in: folder, recursive: false)
        let bytes = try original.map { try Data(contentsOf: $0.url) }
        try await checkInvalidFolderSelections(image: image, root: root, loader: loader)
        let book = try await loader.load(.imageInFolder(image: image, folder: folder))
        try require(book.pages == original && book.initialIndex == 1, "Selected image lost sibling pages, order or initial page.")
        try require(book.title == folder.lastPathComponent && book.sourceURL == folder, "Image-folder book identity changed.")
        try require(try original.map { try Data(contentsOf: $0.url) } == bytes, "Image-folder import modified the source.")
        let pngFolder = root.appendingPathComponent("folder.png")
        try FileManager.default.createDirectory(at: pngFolder, withIntermediateDirectories: true)
        try bytes[0].write(to: pngFolder.appendingPathComponent("1.png"))
        let folderBook = try await loader.load(.file(pngFolder))
        try require(folderBook.pages.count == 1 && folderBook.title == "folder.png", "Image extension disguised a folder as an image.")
        print("Image-folder checks passed: wrong folder, missing/hidden image, empty folder, image-named folder, order, selected page, source preservation")
    }
    private static func checkInvalidFolderSelections(image: URL, root: URL, loader: ComicBookLoader) async throws {
        let folder = image.deletingLastPathComponent()
        let other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        // Even a same-named image in a different folder must not replace the selection.
        try Data(contentsOf: image).write(to: other.appendingPathComponent(image.lastPathComponent))
        do {
            _ = try await loader.load(.imageInFolder(image: image, folder: other))
            throw ImageInputFailure.failed("Wrong selected folder was accepted.")
        } catch ComicImportError.wrongImageFolder { }
        let empty = root.appendingPathComponent("empty-selection")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        for candidate in [folder.appendingPathComponent("missing.png"), empty.appendingPathComponent("missing.png")] {
            do {
                _ = try await loader.load(.imageInFolder(image: candidate, folder: candidate.deletingLastPathComponent()))
                throw ImageInputFailure.failed("Missing selected image silently opened another page.")
            } catch ComicImportError.selectedImageMissing { }
        }
        let hidden = other.appendingPathComponent(".hidden.png")
        try Data(contentsOf: image).write(to: hidden)
        do {
            _ = try await loader.load(.imageInFolder(image: hidden, folder: other))
            throw ImageInputFailure.failed("Excluded selected image silently opened another page.")
        } catch ComicImportError.selectedImageMissing { }
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
