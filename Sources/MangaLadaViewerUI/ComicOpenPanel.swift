import AppKit
import MangaLadaCore

@MainActor
public enum ComicOpenPanel {
    public static func choose(folderOnly: Bool = false) async throws -> ComicInput? {
        try await choose(folderOnly: folderOnly, select: selectedURL)
    }
    // The selection callback is the system-dialog boundary; file access remains in Import.
    static func choose(folderOnly: Bool = false, select: @MainActor (NSOpenPanel) async -> URL?) async throws -> ComicInput? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = !folderOnly
        panel.allowsMultipleSelection = false
        panel.title = folderOnly ? "만화 폴더 열기" : "만화 파일 또는 폴더 열기"
        panel.message = "ZIP·CBZ·7z·CB7·RAR·CBR·PDF·이미지·폴더"
        let siblings = NSButton(checkboxWithTitle: "이미지의 앞뒤 페이지도 함께 열기", target: nil, action: nil)
        siblings.state = .off
        siblings.sizeToFit()
        if !folderOnly {
            panel.accessoryView = siblings
            panel.isAccessoryViewDisclosed = true
        }
        guard let url = await select(panel) else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard ImageFileScanner.isSupportedImage(url),
              try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory != true else { return .file(url) }
        guard siblings.state == .on else { return .externalFile(url) }
        return await chooseImageFolder(for: url, select: select)
    }
    private static func chooseImageFolder(for image: URL, select: @MainActor (NSOpenPanel) async -> URL?) async -> ComicInput? {
        let folder = image.deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.directoryURL = folder
        panel.title = "같은 폴더의 페이지 함께 열기"; panel.prompt = "이 폴더 열기"
        panel.message = "이미지가 있는 폴더를 선택하면 앞뒤 페이지도 열립니다.\n취소하면 현재 책을 유지합니다."
        guard let selectedFolder = await select(panel) else { return nil }
        return .imageInFolder(image: image, folder: selectedFolder)
    }
    private static func selectedURL(in panel: NSOpenPanel) async -> URL? {
        await present(panel) == .OK ? panel.url : nil
    }
    /// Attach system file dialogs to the app window without blocking its event loop.
    public static func present(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            // Accessibility actions can arrive while the app has no active key/main window.
            let host = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
            if let window = host {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else {
                panel.begin { continuation.resume(returning: $0) }
            }
        }
    }
}
