import SwiftUI

@main
struct MangaLadaMacApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Viewer") {
                Button("Open Image...") {
                    Task { await appState.openImageFromPanel() }
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
