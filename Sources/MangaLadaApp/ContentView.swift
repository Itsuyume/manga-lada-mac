import MangaLadaViewerUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            TranslatorActions()
            Divider()
            TranslatorBody(state: state, reading: state.reading)
            TranslatorFooter()
        }.tint(MangaUI.accent).background(.background)
            .overlay(ComicKeyboard(handle: state.handleKey).frame(width: 0, height: 0))
            .comicFileDrop(open: { url in Task { await state.open(url) } }, failure: { state.errorMessage = $0 })
            .sheet(isPresented: $state.showSettings) { TranslatorSettingsView(state: state) }
            .alert("작업 확인", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
                Button("확인", role: .cancel) { state.errorMessage = nil }
            } message: { Text(state.errorMessage ?? "") }
    }
}

private struct TranslatorBody: View {
    @ObservedObject var state: AppState
    @ObservedObject var reading: ReadingSettings
    var body: some View {
        HStack(spacing: 0) {
            if reading.showThumbnails {
                ThumbnailSidebar(pages: state.pages.map(\.url), index: state.currentIndex, badges: thumbnailBadges, select: state.select)
                Divider()
            }
            if state.pages.isEmpty { TranslatorEmptyState() }
            else { VStack(spacing: 0) {
                canvasHeader
                ComicPageCanvas(pages: state.displayPages, index: state.currentIndex, settings: reading, revision: state.imageRevision,
                                   selection: state.isSelectingRegion ? Binding(get: { state.selectedRegion }, set: { state.selectRegion($0) }) : nil,
                                   regions: state.showInspector || state.isSelectingRegion ? state.currentReview?.blocks ?? [] : [],
                                   selectedRegionID: Binding(get: { state.selectedBlockID }, set: { state.focusBlock($0) }),
                                   onMoveRegion: moveRegion,
                                   useLetteringCoordinates: state.mode == .translated && !state.isSelectingRegion,
                                   onSelect: state.select)
                .allowsHitTesting(!state.isSelectingRegion || !state.isBusy)
                // Laid out below the page, not over it, so markers and drags near the edge stay reachable.
                ReadingControls(settings: reading, index: state.currentIndex, total: state.pages.count, navigate: state.select)
                    .padding(.vertical, 8).frame(maxWidth: .infinity).background(MangaUI.canvas)
            } }
            if state.showInspector && !state.pages.isEmpty { Divider(); TranslationInspector(state: state).frame(width: 300) }
        }.overlay {
            if state.isLoading { ProgressView("페이지를 여는 중…").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }
    }
    private var showsNotice: Bool {
        !state.isSelectingRegion && state.mode == .translated
            && (state.currentResult == nil || state.failures[state.currentIndex] != nil)
    }
    private var showsLegend: Bool {
        (state.showInspector || state.isSelectingRegion) && state.currentReview?.blocks.isEmpty == false
    }
    /// Selection controls, page notice and region legend share one strip above the page.
    @ViewBuilder private var canvasHeader: some View {
        if state.isSelectingRegion || showsNotice || showsLegend {
            VStack(spacing: 8) {
                if state.isSelectingRegion { RegionSelectionControls(state: state) }
                else if showsNotice {
                    pageNotice.font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                }
                if showsLegend { RecognizedRegionLegend(state: state) }
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity).background(MangaUI.canvas)
        }
    }
    private var thumbnailBadges: [Int: ThumbnailBadge] {
        var badges: [Int: ThumbnailBadge] = [:]
        for index in state.completed { badges[index] = .completed }
        for (index, result) in state.results where !result.reviewWarnings.isEmpty { badges[index] = .needsReview }
        for index in state.failures.keys { badges[index] = .failed }
        // A failed page with recognized text is reviewable; that is the actionable state.
        for index in state.pendingPages.keys { badges[index] = .needsReview }
        if state.isBusy, let index = state.processingIndex { badges[index] = .processing }
        return badges
    }
    private var moveRegion: ((UUID, CGSize) -> Void)? {
        guard !state.isBusy, !state.isLoading, state.mode == .translated else { return nil }
        return { id, delta in state.moveLettering(id, by: delta) }
    }
    @ViewBuilder private var pageNotice: some View {
        if state.pendingPages[state.currentIndex] != nil {
            Label("번역 미완료 · 검수창에서 원문과 번역을 수정하세요", systemImage: "pencil.circle")
        } else if state.failures[state.currentIndex] != nil {
            Label(state.currentResult == nil ? "번역 실패 · 검수창에서 재시도하세요" : "재번역 실패 · 이전 저장본 표시 중", systemImage: "exclamationmark.triangle")
        } else if state.currentResult == nil {
            Label(state.isBusy ? "현재 페이지 번역 대기 중" : "아직 번역 전 · 전체 번역 시작을 누르세요", systemImage: "clock")
        }
    }
}

private struct TranslatorEmptyState: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        ComicDropPrompt(symbol: "character.bubble", title: "일본어·영어 만화를 한국어로",
                        message: "책을 여기로 끌어다 놓거나 열기를 누르세요.\n말풍선과 효과음을 번역해 지정한 폴더에 자동 저장합니다.",
                        formats: ["ZIP", "7z", "RAR", "CBZ · CBR", "PDF", "이미지 · 폴더"],
                        steps: ["책 열기", "글자 인식 · 번역", "검수 · 저장"],
                        openFile: { state.chooseBook() }, openFolder: { state.chooseBook(folderOnly: true) })
    }
}
