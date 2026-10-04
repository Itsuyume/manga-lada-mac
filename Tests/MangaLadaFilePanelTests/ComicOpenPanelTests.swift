import AppKit
import Foundation
import MangaLadaCore
import MangaLadaImport

@main
@MainActor
struct ComicOpenPanelTests {
    static func main() async throws {
        let checks = Self()
        try await checks.testSingleImageNeedsOneSelectionAndSurvivesSourceRemoval()
        try await checks.testSiblingPagesRequireOptInAndKeepTheSelectedPage()
        try await checks.testCancellingEitherDialogReturnsNoInput()
        try await checks.testDirectoryAndArchiveSelectionsNeverAskForASecondFolder()
        print("File panel checks passed: one-selection image import, long names, opt-in siblings, cancel, folder/archive selection, source preservation")
    }
    func testSingleImageNeedsOneSelectionAndSurvivesSourceRemoval() async throws {
        try await withFixture { image, root, bytes in
            var selections = 0
            let input = try await ComicOpenPanel.choose { panel in
                selections += 1
                return selections == 1 ? image : nil
            }
            check(selections == 1, "Single image required a second folder selection.")
            guard case .externalFile(let selected) = input else {
                throw Failure.failed("Single-image selection requested a parent folder.")
            }
            check(selected == image)
            let loader = ComicBookLoader(extractionRoot: root.appendingPathComponent("cache"))
            let book = try await loader.load(try unwrap(input))
            check(book.pages.count == 1 && book.initialIndex == 0)
            check(try Data(contentsOf: image) == bytes)
            try FileManager.default.removeItem(at: image)
            check(try Data(contentsOf: book.pages[0].url) == bytes)
        }
    }

    func testSiblingPagesRequireOptInAndKeepTheSelectedPage() async throws {
        try await withFixture { image, root, bytes in
            var selections = 0
            let input = try await ComicOpenPanel.choose { panel in
                selections += 1
                if selections == 1 {
                    guard let option = panel.accessoryView as? NSButton else {
                        check(false, "Sibling-page choice is missing."); return nil
                    }
                    check(option.state == .off)
                    option.state = .on
                    return image
                }
                check(panel.canChooseDirectories && !panel.canChooseFiles)
                check(panel.directoryURL?.standardizedFileURL == image.deletingLastPathComponent().standardizedFileURL)
                let width = (panel.message as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
                check(width < 600, "Long names widened the folder prompt beyond a compact dialog.")
                print("Long-name folder prompt width: \(Int(width)) pt")
                return image.deletingLastPathComponent()
            }
            check(selections == 2)
            guard case .imageInFolder = input else { throw Failure.failed("Explicit sibling selection was lost.") }
            let loader = ComicBookLoader(extractionRoot: root.appendingPathComponent("cache"))
            let book = try await loader.load(try unwrap(input))
            check(book.pages.count == 2 && book.initialIndex == 1)
            check(try Data(contentsOf: book.pages[book.initialIndex].url) == bytes)
        }
    }

    func testCancellingEitherDialogReturnsNoInput() async throws {
        let cancelled = try await ComicOpenPanel.choose { _ in nil }
        check(cancelled == nil)
        try await withFixture { image, _, bytes in
            var selections = 0
            let input = try await ComicOpenPanel.choose { panel in
                selections += 1
                guard selections == 1 else { return nil }
                (panel.accessoryView as? NSButton)?.state = .on
                return image
            }
            check(input == nil && selections == 2)
            check(try Data(contentsOf: image) == bytes)
        }
    }

    func testDirectoryAndArchiveSelectionsNeverAskForASecondFolder() async throws {
        try await withFixture { _, root, bytes in
            let imageNamedFolder = root.appendingPathComponent("folder.png")
            try FileManager.default.createDirectory(at: imageNamedFolder, withIntermediateDirectories: true)
            try bytes.write(to: imageNamedFolder.appendingPathComponent("1.png"))
            let archive = root.appendingPathComponent("book.cbz")
            try Data().write(to: archive)
            for (url, folderOnly) in [(imageNamedFolder, true), (imageNamedFolder, false), (archive, false)] {
                var selections = 0
                let input = try await ComicOpenPanel.choose(folderOnly: folderOnly) { panel in
                    selections += 1
                    if folderOnly { check(panel.accessoryView == nil) }
                    (panel.accessoryView as? NSButton)?.state = .on
                    return selections == 1 ? url : nil
                }
                check(selections == 1)
                guard case .file(let selected) = input else { throw Failure.failed("Non-image selection changed.") }
                check(selected == url)
            }
        }
    }

    private func check(_ condition: Bool, _ message: String = "File panel behavior mismatch", file: StaticString = #file, line: UInt = #line) {
        guard condition else { fatalError(message, file: file, line: line) }
    }
    private func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure.failed("Required file input missing.") }
        return value
    }
    private enum Failure: Error { case failed(String) }
    private func withFixture(_ body: @MainActor (URL, URL, Data) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("manga-panel-" + UUID().uuidString)
        let folder = root.appendingPathComponent("uuid=" + String(repeating: "abcdef0123456789", count: 13) + "&library=1.png")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let image = folder.appendingPathComponent("02_" + String(repeating: "日本語_", count: 20) + ".png")
        let bitmap = try unwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32))
        for x in 0..<2 { for y in 0..<2 { bitmap.setColor(NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1), atX: x, y: y) } }
        let bytes = try unwrap(bitmap.representation(using: .png, properties: [:]))
        try bytes.write(to: folder.appendingPathComponent("01.png"))
        try bytes.write(to: image)
        try await body(image, root, bytes)
    }
}
