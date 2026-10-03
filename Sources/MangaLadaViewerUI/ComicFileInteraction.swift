import AppKit
import MangaLadaCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public enum ComicOpenPanel {
    public static func choose(folderOnly: Bool = false) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = !folderOnly
        panel.allowsMultipleSelection = false
        panel.title = folderOnly ? "만화 폴더 열기" : "만화 파일 또는 폴더 열기"
        panel.message = "ZIP·CBZ·7z·CB7·RAR·CBR·PDF·이미지·폴더"
        return await present(panel) == .OK ? panel.url : nil
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

public extension View {
    func comicFileDrop(open: @escaping @MainActor (ComicInput) -> Void, failure: @escaping @MainActor (String) -> Void) -> some View {
        modifier(ComicFileDrop(open: open, failure: failure))
    }
}

private struct ComicFileDrop: ViewModifier {
    let open: @MainActor (ComicInput) -> Void
    let failure: @MainActor (String) -> Void
    @State private var targeted = false
    func body(content: Content) -> some View {
        content.overlay { if targeted { RoundedRectangle(cornerRadius: 8).stroke(MangaUI.accent, lineWidth: 3).padding(8) } }
            .onDrop(of: [UTType.fileURL.identifier, UTType.image.identifier], isTargeted: $targeted) { providers in
                guard let provider = providers.first else { return false }
                if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                        Task { @MainActor in
                            if let error { failure(error.localizedDescription); return }
                            guard let data else { failure("드롭한 이미지 데이터를 읽을 수 없습니다."); return }
                            open(.image(data))
                        }
                    }
                    return true
                }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let error { Task { @MainActor in failure(error.localizedDescription) }; return }
                    let url = Self.fileURL(from: item)
                    Task { @MainActor in
                        guard let url else { failure("드롭한 항목을 파일로 읽을 수 없습니다."); return }
                        open(.externalFile(url))
                    }
                }
                return true
            }
    }
    nonisolated private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
}
