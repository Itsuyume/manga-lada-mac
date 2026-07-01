import SwiftUI

@main
struct MangaLadaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 680)
                .onAppear {
                    appDelegate.installOpenFilesHandler { urls in
                        guard let firstURL = urls.first else {
                            return
                        }
                        Task { await appState.openDroppedURL(firstURL) }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Viewer") {
                Button("Open Image or ZIP...") {
                    Task { await appState.openFileFromPanel() }
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Translate Current Page") {
                    Task { await appState.translateCurrentPage(force: true) }
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Previous Page") {
                    appState.goToPreviousPage()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button("Next Page") {
                    appState.goToNextPage()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingOpenURLs: [URL] = []
    private var openFilesHandler: (([URL]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let argumentURLs = CommandLine.arguments
            .dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        routeOpenURLs(argumentURLs)
        ensureWindowIsVisible()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        routeOpenURLs(urls)
        ensureWindowIsVisible()
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        routeOpenURLs(urls)
        ensureWindowIsVisible()
    }

    func installOpenFilesHandler(_ handler: @escaping ([URL]) -> Void) {
        openFilesHandler = handler
        if !pendingOpenURLs.isEmpty {
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            handler(urls)
        }
    }

    private func routeOpenURLs(_ urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        if let openFilesHandler {
            openFilesHandler(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    private func ensureWindowIsVisible() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if NSApp.windows.isEmpty {
                NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
