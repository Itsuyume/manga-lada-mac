import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

@main
struct MangaReaderApp: App {
    @NSApplicationDelegateAdaptor(ComicAppDelegate.self) private var delegate
    @StateObject private var state = ReaderState()
    var body: some Scene {
        Window(MangaLadaEdition.readerName, id: "reader") {
            ReaderView().environmentObject(state).frame(minWidth: 820, minHeight: 600)
                .onAppear { delegate.installOpenHandler { url in Task { await state.open(url) } } }
        }.defaultSize(width: 1140, height: 800).windowStyle(.hiddenTitleBar)
            .commands {
                ComicPasteCommands(open: { input in Task { await state.open(input) } }, failure: { state.errorMessage = $0 })
                CommandGroup(replacing: .newItem) { Button("만화 열기…") { state.chooseBook() }.keyboardShortcut("o") }
                CommandMenu("읽기") {
                    Button("다음 페이지") { state.next() }.keyboardShortcut(.space, modifiers: [])
                    Button("첫 페이지") { state.select(0) }.keyboardShortcut(.home, modifiers: [])
                    Button("마지막 페이지") { state.select(state.pages.count - 1) }.keyboardShortcut(.end, modifiers: [])
                    Divider()
                    Button("확대") { state.reading.zoomIn() }.keyboardShortcut("+", modifiers: .command)
                    Button("축소") { state.reading.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                    Button("전체화면") { state.reading.toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
                }
            }
    }
}
