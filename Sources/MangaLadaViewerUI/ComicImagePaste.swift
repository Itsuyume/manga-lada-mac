import AppKit
import MangaLadaCore
import SwiftUI

@MainActor
public enum ComicImagePaste {
    private static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg"), .init("public.heic")]
    public static func hasImage(in pasteboard: NSPasteboard = .general) -> Bool {
        if pasteboard.availableType(from: imageTypes) != nil { return true }
        if let url = fileURL(from: pasteboard), ImageFileScanner.isSupportedImage(url) { return true }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }
    public static func input(from pasteboard: NSPasteboard = .general) throws -> ComicInput {
        for type in imageTypes {
            if let data = pasteboard.data(forType: type), !data.isEmpty { return .image(data) }
        }
        if let url = fileURL(from: pasteboard) { return .externalFile(url) }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first, let data = image.tiffRepresentation { return .image(data) }
        throw ComicPasteError.noImage
    }
    private static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
    }
}

public enum ComicPasteError: LocalizedError {
    case noImage
    public var errorDescription: String? { "복사한 이미지나 파일이 없습니다. 사진 앱에서 이미지를 복사한 후 다시 붙여넣어주세요." }
}

/// Image input works from any focus; ordinary text retains the editor's responder actions.
public struct ComicPasteCommands: Commands {
    private let open: @MainActor (ComicInput) -> Void
    private let failure: @MainActor (String) -> Void
    public init(open: @escaping @MainActor (ComicInput) -> Void, failure: @escaping @MainActor (String) -> Void) {
        self.open = open; self.failure = failure
    }
    public var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("오려두기") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }.keyboardShortcut("x")
            Button("복사하기") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }.keyboardShortcut("c")
            Button("붙여넣기") { pasteImage(unlessEditingText: true) }.keyboardShortcut("v")
            Button("이미지 붙여넣기") { pasteImage(unlessEditingText: false) }.keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            Button("전체 선택") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }.keyboardShortcut("a")
        }
    }
    private func pasteImage(unlessEditingText: Bool) {
        if unlessEditingText, NSApp.keyWindow?.firstResponder is NSTextView,
           !ComicImagePaste.hasImage() {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil); return
        }
        do { open(try ComicImagePaste.input()) }
        catch { failure(error.localizedDescription) }
    }
}
