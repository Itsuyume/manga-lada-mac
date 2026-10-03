import MangaLadaViewerUI
import SwiftUI

@main
struct MangaLadaMacApp: App {
    @NSApplicationDelegateAdaptor(ComicAppDelegate.self) private var delegate
    @StateObject private var state = AppState()
    var body: some Scene {
        Window("Manga translator", id: "translator") {
            ContentView().environmentObject(state).frame(minWidth: 980, minHeight: 680)
                .onAppear { delegate.installOpenHandler { url in Task { await state.open(url) } } }
        }.defaultSize(width: 1180, height: 820).windowStyle(.hiddenTitleBar)
            .commands {
                ComicPasteCommands(open: { input in Task { await state.open(input) } }, failure: { state.errorMessage = $0 })
                CommandGroup(replacing: .newItem) { Button("만화 열기…") { state.chooseBook() }.keyboardShortcut("o") }
                CommandMenu("번역") {
                    Button("전체 번역 시작") { state.startTranslation() }.keyboardShortcut("t", modifiers: .command)
                    Button("현재 페이지 다시 번역") { state.startTranslation(onlyCurrent: true, force: true) }.disabled(state.isBusy)
                    Button("중단") { state.stop() }.disabled(!state.isBusy)
                    Divider()
                    Button("현재 PNG 저장…") { state.exportCurrentPNG() }.keyboardShortcut("s", modifiers: [.command, .shift])
                    Button("완성본 CBZ 저장…") { state.exportCBZ() }
                    Button("Manga Reader로 읽기") { state.openInReader() }
                }
                CommandMenu("화면") {
                    Button("확대") { state.reading.zoomIn() }.keyboardShortcut("+", modifiers: .command)
                    Button("축소") { state.reading.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                    Button("전체화면") { state.reading.toggleFullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
                }
                CommandGroup(replacing: .appSettings) { Button("설정…") { state.showSettings = true }.keyboardShortcut(",").disabled(state.isBusy) }
            }
    }
}
