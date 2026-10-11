import AppKit
import MangaLadaViewerUI
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var state: ReaderState
    @State private var isFullScreen = false
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ReaderBody(state: state, reading: state.reading)
        }.tint(MangaUI.accent).background(.background)
            // The header shares the title bar row with the window buttons instead of sitting below it.
            .ignoresSafeArea(.container, edges: .top)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in isFullScreen = true }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in isFullScreen = false }
            .overlay(ComicKeyboard(handle: state.handleKey).frame(width: 0, height: 0))
            .comicFileDrop(open: { url in Task { await state.open(url) } }, failure: { state.errorMessage = $0 })
            .alert("작업 확인", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
                Button("확인", role: .cancel) { state.errorMessage = nil }
            } message: { Text(state.errorMessage ?? "") }
    }
    private var header: some View {
        HStack(spacing: 12) {
            ThumbnailToggleButton(settings: state.reading).disabled(state.pages.isEmpty)
            AppBrand("Manga Reader", symbol: "book.closed")
            Text(state.title.isEmpty ? "나만의 만화 서재" : state.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("파일 열기", systemImage: "doc") { state.chooseBook() }
            Button("폴더 열기", systemImage: "folder") { state.chooseBook(folderOnly: true) }
            Button("이 책 번역하기", systemImage: "character.bubble.ja") { state.openInTranslator() }
                .buttonStyle(.borderedProminent).disabled(state.pages.isEmpty || state.isLoading)
            bookmarkMenu
            Button { state.reading.toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("전체화면")
        }.buttonStyle(.bordered).controlSize(.small).padding(.leading, isFullScreen ? 14 : 78).padding(.trailing, 14)
            .padding(.top, 4).padding(.bottom, 6)
    }
    private var bookmarkMenu: some View {
        Menu {
            Button(state.bookmarks.contains(state.index) ? "현재 책갈피 제거" : "현재 페이지 책갈피") { state.toggleBookmark() }
            Divider()
            ForEach(state.bookmarks.sorted(), id: \.self) { number in Button("\(number + 1)페이지") { state.select(number) } }
        } label: { Image(systemName: state.bookmarks.contains(state.index) ? "bookmark.fill" : "bookmark") }
            .fixedSize().disabled(state.pages.isEmpty).help("책갈피")
    }
}

private struct ReaderControlBar: View {
    @ObservedObject var state: ReaderState
    @ObservedObject var reading: ReadingSettings
    var body: some View {
        // Progress and the key hint flank the controls only when the row has room for them.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                ProgressView(value: Double(state.index), total: Double(max(1, state.pages.count - 1))).progressViewStyle(.linear)
                    .frame(width: 140).frame(maxWidth: .infinity, alignment: .leading)
                controls
                Text(reading.direction == .rightToLeft ? "← 다음 · → 이전 · Space 다음" : "→ 다음 · ← 이전 · Space 다음")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            controls
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(maxWidth: .infinity).background(MangaUI.canvas)
    }
    private var controls: some View {
        ReadingControls(settings: reading, index: state.index, total: state.pages.count, navigate: state.select)
    }
}

private struct ReaderBody: View {
    @ObservedObject var state: ReaderState
    @ObservedObject var reading: ReadingSettings
    var body: some View {
        HStack(spacing: 0) {
            if reading.showThumbnails {
                ThumbnailSidebar(pages: state.pages.map(\.url), index: state.index, select: state.select).id(state.imageRevision)
                Divider()
            }
            if state.pages.isEmpty {
                ComicDropPrompt(symbol: "book.pages", title: "만화를 펼쳐보세요",
                                message: "파일이나 폴더를 여기로 끌어다 놓거나 열기를 누르세요.",
                                formats: ["ZIP", "7z", "RAR", "CBZ · CBR", "PDF", "이미지"],
                                openFile: { state.chooseBook() }, openFolder: { state.chooseBook(folderOnly: true) })
            } else {
                VStack(spacing: 0) {
                    ComicPageCanvas(pages: state.pages.map(\.url), index: state.index, settings: reading,
                                    revision: state.imageRevision, onSelect: state.select)
                    ReaderControlBar(state: state, reading: reading)
                }
            }
        }.overlay { if state.isLoading { ProgressView().controlSize(.large).padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }
}
