import MangaLadaViewerUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            TranslatorHeader()
            Divider()
            TranslatorActions()
            if state.isSelectingRegion { RegionSelectionControls(state: state) }
            Divider()
            ReadingControls(settings: state.reading, index: state.currentIndex, total: state.pages.count, navigate: state.select)
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
                ThumbnailSidebar(pages: state.pages.map(\.url), index: state.currentIndex, completed: state.completed, select: state.select)
                Divider()
            }
            if state.pages.isEmpty { TranslatorEmptyState() }
            else { VStack(spacing: 0) {
                if (state.showInspector || state.isSelectingRegion) && state.currentResult?.translation.blocks.isEmpty == false {
                    RecognizedRegionLegend(state: state)
                }
                ComicPageCanvas(pages: state.displayPages, index: state.currentIndex, settings: reading, revision: state.imageRevision,
                                   selection: state.isSelectingRegion ? Binding(get: { state.selectedRegion }, set: state.selectRegion) : nil,
                                   regions: state.showInspector || state.isSelectingRegion ? state.currentResult?.translation.blocks ?? [] : [],
                                   selectedRegionID: Binding(get: { state.selectedBlockID }, set: state.focusBlock), onSelect: state.select)
                .allowsHitTesting(!state.isSelectingRegion || !state.isBusy)
            } }
            if state.showInspector && !state.pages.isEmpty { Divider(); TranslationInspector(state: state).frame(width: 260) }
        }.overlay {
            if state.isLoading { ProgressView("페이지를 여는 중…").padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
        }.overlay(alignment: .topLeading) {
            if !state.pages.isEmpty && !state.isSelectingRegion && state.mode == .translated && state.currentResult == nil {
                Label(state.isBusy ? "현재 페이지 번역 대기 중" : "아직 번역 전 · 전체 번역 시작을 누르세요", systemImage: "clock")
                    .font(.system(size: 12, weight: .medium)).padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(12)
            }
        }
    }
}

private struct TranslatorEmptyState: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "character.bubble.ja").font(.system(size: 50, weight: .light)).foregroundStyle(.white.opacity(0.65))
            Text("일본어 만화를 한국어로").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
            Text("책을 열면 말풍선과 효과음을 번역해 자동 저장합니다.").foregroundStyle(.white.opacity(0.65))
            Button("만화 열기", systemImage: "folder.badge.plus") { state.chooseBook() }.buttonStyle(.borderedProminent).controlSize(.large)
            Text("ZIP · 7z · RAR · CBZ · CBR · PDF · 이미지 · 폴더").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(MangaUI.canvas)
    }
}
