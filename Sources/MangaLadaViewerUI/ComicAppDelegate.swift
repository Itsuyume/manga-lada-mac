import AppKit
import MangaLadaCore

@MainActor
public final class ComicAppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []
    private var handler: ((ComicInput) -> Void)?
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let urls = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if let first = urls.first { route(first) }
        NSApp.activate(ignoringOtherApps: true)
    }
    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    public func application(_ app: NSApplication, open urls: [URL]) {
        if let first = urls.first { route(first) }; NSApp.activate(ignoringOtherApps: true)
    }
    public func application(_ app: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { route(URL(fileURLWithPath: first)) }
        app.reply(toOpenOrPrint: .success); NSApp.activate(ignoringOtherApps: true)
    }
    public func installOpenHandler(_ handler: @escaping (ComicInput) -> Void) {
        self.handler = handler
        if let last = pending.last { pending.removeAll(); handler(.externalFile(last)) }
    }
    private func route(_ url: URL) {
        if let handler { handler(.externalFile(url)) } else { pending.append(url) }
    }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
