import MangaLadaCore
import SwiftUI

struct TranslatorActions: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            openMenu
            Toggle("자동 번역", isOn: $state.autoTranslate).toggleStyle(.switch).controlSize(.mini)
                .help("파일을 열면 자동으로 번역합니다.")
            Button(translationButtonTitle, systemImage: "captions.bubble") { state.startTranslation() }
                .buttonStyle(.borderedProminent).disabled(state.pages.isEmpty || state.isBusy || state.isLoading || allPagesComplete)
            if state.isBusy { Button("중단", systemImage: "stop.fill") { state.stop() } }
            Button(state.isSelectingRegion ? "영역 지정 끝내기" : "영역 지정", systemImage: "viewfinder") {
                state.isSelectingRegion.toggle(); state.selectedRegion = nil; state.placementBlockID = nil
            }.disabled(state.pages.isEmpty || state.isBusy || state.isLoading)
            Spacer(minLength: 6)
            Picker("원문 / 번역", selection: $state.mode) {
                Text("원문").tag(AppMode.imageOnly); Text("번역").tag(AppMode.translated)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 112).fixedSize()
            Button(state.showInspector ? "검수 닫기" : "검수 열기", systemImage: "sidebar.right") {
                state.showInspector.toggle()
            }.disabled(state.pages.isEmpty).keyboardShortcut("i", modifiers: [.command, .option])
                .help("번역 검수창 열기 / 닫기 · ⌥⌘I · 임시 수정은 유지됩니다.")
            Menu {
                Button("완성본 저장 폴더 지정…") { state.chooseOutputFolder() }.disabled(state.isBusy)
                Button("결과 폴더 보기") { state.revealOutput() }
                Divider()
                Button("현재 PNG 저장…") { state.exportCurrentPNG() }.disabled(state.currentResult == nil)
                Button("완성본 CBZ 저장…") { state.exportCBZ() }.disabled(state.results.count != state.pages.count || state.results.isEmpty || state.isBusy || !state.failures.isEmpty)
            } label: { Label("저장", systemImage: "square.and.arrow.down") }.fixedSize()
            Button("Reader로 읽기", systemImage: "book") { state.openInReader() }
                .labelStyle(.iconOnly).disabled(state.results.isEmpty || state.isBusy).help("Reader로 읽기")
            Button("설정", systemImage: "slider.horizontal.3") { state.showSettings = true }
                .labelStyle(.iconOnly).disabled(state.isBusy).help("모델·글꼴 설정")
        }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 14).padding(.vertical, 8).background(.bar)
    }
    private var openMenu: some View {
        Menu {
            Button("파일 열기…", systemImage: "doc") { state.chooseBook() }
            Button("폴더 열기…", systemImage: "folder") { state.chooseBook(folderOnly: true) }
        } label: {
            Label("열기", systemImage: "folder")
        } primaryAction: {
            state.chooseBook()
        }.fixedSize().help("파일 열기 · 화살표를 누르면 폴더도 선택할 수 있습니다.")
    }
    private var allPagesComplete: Bool { !state.pages.isEmpty && state.results.count == state.pages.count && state.failures.isEmpty }
    private var translationButtonTitle: String {
        if state.isBusy { return "번역 진행 중…" }
        if allPagesComplete { return "전체 번역 완료" }
        return state.results.isEmpty ? "전체 번역 시작" : "이어서 번역"
    }
}

struct TranslatorFooter: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            if !state.pages.isEmpty { ProgressView(value: state.progress).progressViewStyle(.linear).frame(height: 3) }
            HStack(spacing: 8) {
                Circle().fill(state.isBusy ? .orange : state.failures.isEmpty ? .green : .red).frame(width: 6, height: 6)
                Text(state.statusMessage).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                Text("완료 \(state.completed.count) · 실패 \(state.failures.count)").monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 11)).padding(.horizontal, 18).padding(.vertical, 9)
        }.background(.bar)
    }
}
