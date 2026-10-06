import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

struct TranslatorActions: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            ThumbnailToggleButton(settings: state.reading).labelStyle(.iconOnly).disabled(state.pages.isEmpty)
            openMenu
            bookTitle
            Spacer(minLength: 12)
            Picker("원문 / 번역", selection: $state.mode) {
                Text("원문").tag(AppMode.imageOnly); Text("번역").tag(AppMode.translated)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 112).fixedSize().disabled(state.pages.isEmpty)
            Spacer(minLength: 12)
            Button(state.isSelectingRegion ? "영역 지정 끝내기" : "영역 지정", systemImage: "viewfinder") {
                state.isSelectingRegion.toggle(); state.selectedRegion = nil; state.placementBlockID = nil
            }.disabled(state.pages.isEmpty || state.isBusy || state.isLoading)
                .tint(state.isSelectingRegion ? MangaUI.accent : nil)
            saveMenu
            Button("Reader로 읽기", systemImage: "book") { state.openInReader() }
                .labelStyle(.iconOnly).disabled(state.results.isEmpty || state.isBusy).help("Reader로 읽기")
            Button("설정", systemImage: "slider.horizontal.3") { state.showSettings = true }
                .labelStyle(.iconOnly).disabled(state.isBusy).help("모델·글꼴 설정")
            Button(state.showInspector ? "검수 닫기" : "검수 열기", systemImage: "sidebar.right") {
                state.showInspector.toggle()
            }.labelStyle(.iconOnly).disabled(state.pages.isEmpty).keyboardShortcut("i", modifiers: [.command, .option])
                .tint(state.showInspector ? MangaUI.accent : nil)
                .help("번역 검수창 열기 / 닫기 · ⌥⌘I · 임시 수정은 유지됩니다.")
            Divider().frame(height: 20)
            Button { state.startTranslation() } label: {
                HStack(spacing: 6) {
                    if state.isBusy { ProgressView().controlSize(.mini) } else { Image(systemName: "captions.bubble") }
                    Text(translationButtonTitle).monospacedDigit()
                }
            }.buttonStyle(.borderedProminent).disabled(state.pages.isEmpty || state.isBusy || state.isLoading || allPagesComplete)
            if state.isBusy {
                Button("중단", systemImage: "stop.fill") { state.stop() }.labelStyle(.iconOnly).help("현재 작업 중단")
            }
        }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 14).padding(.vertical, 9).background(.bar)
    }
    @ViewBuilder private var bookTitle: some View {
        if !state.pages.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(state.pages.count)쪽 · 저장 \(state.outputRoot?.lastPathComponent ?? "폴더 미지정")")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.truncationMode(.middle).padding(.leading, 2).help(state.outputRoot?.path ?? "완성본 저장 폴더를 아직 지정하지 않았습니다.")
        }
    }
    private var openMenu: some View {
        Menu {
            Button("파일 열기…", systemImage: "doc") { state.chooseBook() }
            Button("폴더 열기…", systemImage: "folder") { state.chooseBook(folderOnly: true) }
            Divider()
            Toggle("파일을 열면 자동 번역", isOn: $state.autoTranslate)
        } label: {
            Label("열기", systemImage: "folder")
        } primaryAction: {
            state.chooseBook()
        }.fixedSize().help("파일 열기 · 화살표를 누르면 폴더 열기와 자동 번역 설정이 있습니다.")
    }
    private var saveMenu: some View {
        Menu {
            Button("완성본 저장 폴더 지정…") { state.chooseOutputFolder() }.disabled(state.isBusy)
            Button("결과 폴더 보기") { state.revealOutput() }
            Divider()
            Button("현재 PNG 저장…") { state.exportCurrentPNG() }.disabled(state.currentResult == nil)
            Button("완성본 CBZ 저장…") { state.exportCBZ() }.disabled(state.results.count != state.pages.count || state.results.isEmpty || state.isBusy || !state.failures.isEmpty)
        } label: { Label("저장", systemImage: "square.and.arrow.down") }.fixedSize()
    }
    private var allPagesComplete: Bool { !state.pages.isEmpty && state.results.count == state.pages.count && state.failures.isEmpty }
    private var translationButtonTitle: String {
        if state.isBusy {
            guard let page = state.processingIndex else { return "진행 중…" }
            return "진행 중 \(page + 1)/\(state.pages.count)"
        }
        if allPagesComplete { return "전체 번역 완료" }
        return state.results.isEmpty ? "전체 번역 시작" : "이어서 번역"
    }
}

struct TranslatorFooter: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(state.isBusy ? MangaUI.attention : state.failures.isEmpty ? MangaUI.success : MangaUI.failure).frame(width: 7, height: 7)
            Text(state.statusMessage).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 12)
            if !state.pages.isEmpty {
                ProgressView(value: state.progress).progressViewStyle(.linear).frame(width: 180)
            }
            Text(counts).monospacedDigit().foregroundStyle(.secondary)
        }.font(.system(size: 11)).padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
    }
    private var counts: String {
        let review = state.pendingPages.count
        return "완료 \(state.completed.count) · 실패 \(state.failures.count)" + (review == 0 ? "" : " · 검수 필요 \(review)")
    }
}
