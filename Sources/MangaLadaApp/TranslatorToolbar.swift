import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

struct TranslatorHeader: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        HStack(spacing: 14) {
            AppBrand("Manga translator", symbol: "character.book.closed.ja")
            Text(state.configuration.provider == .ollama ? "일본어 → 한국어 · 로컬" : "일본어 → 한국어 · 저가 API")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(state.configuration.provider == .ollama ? .green : .orange)
                .padding(.horizontal, 8).padding(.vertical, 5).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
            Spacer(minLength: 8)
            Button("파일 열기", systemImage: "doc") { state.chooseBook() }
            Button("폴더 열기", systemImage: "folder") { state.chooseBook(folderOnly: true) }
            Button { state.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.disabled(state.isBusy).help("모델·글꼴 설정")
        }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 14)
    }
}

struct TranslatorActions: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Toggle("열면 자동 번역", isOn: $state.autoTranslate).toggleStyle(.switch).controlSize(.mini)
            Button(translationButtonTitle, systemImage: "captions.bubble") { state.startTranslation() }
                .buttonStyle(.borderedProminent).disabled(state.pages.isEmpty || state.isBusy || state.isLoading || allPagesComplete)
            if state.isBusy { Button("중단", systemImage: "stop.fill") { state.stop() } }
            Button(state.isSelectingRegion ? "영역 지정 끝내기" : "영역 지정", systemImage: "viewfinder") {
                state.isSelectingRegion.toggle(); state.selectedRegion = nil
            }.disabled(state.pages.isEmpty || state.isBusy || state.isLoading)
            Spacer(minLength: 6)
            Picker("원문 / 번역", selection: $state.mode) {
                Text("원문").tag(AppMode.imageOnly); Text("번역").tag(AppMode.translated)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 112).fixedSize()
            Button { state.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("번역 검수 표시 / 숨기기")
            Menu {
                Button("완성본 저장 폴더 지정…") { state.chooseOutputFolder() }.disabled(state.isBusy)
                Button("결과 폴더 보기") { state.revealOutput() }
                Divider()
                Button("현재 PNG 저장…") { state.exportCurrentPNG() }.disabled(state.currentResult == nil)
                Button("완성본 CBZ 저장…") { state.exportCBZ() }.disabled(state.results.count != state.pages.count || state.results.isEmpty || state.isBusy || !state.failures.isEmpty)
            } label: { Label("저장", systemImage: "square.and.arrow.down") }.fixedSize()
            Button("Reader로 읽기", systemImage: "book") { state.openInReader() }.disabled(state.results.isEmpty || state.isBusy)
        }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 18).padding(.vertical, 10).background(.bar)
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
                Text("완료 \(state.results.count) · 실패 \(state.failures.count)").monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 11)).padding(.horizontal, 18).padding(.vertical, 9)
        }.background(.bar)
    }
}
