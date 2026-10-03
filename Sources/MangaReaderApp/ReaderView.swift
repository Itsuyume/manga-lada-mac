import AppKit
import MangaLadaViewerUI
import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var state: ReaderState
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ReadingControls(settings: state.reading, index: state.index, total: state.pages.count, navigate: state.select)
            Divider()
            ReaderBody(state: state, reading: state.reading)
            ReaderFooter(state: state, reading: state.reading)
        }.tint(MangaUI.accent).background(.background)
            .overlay(ComicKeyboard(handle: state.handleKey).frame(width: 0, height: 0))
            .comicFileDrop(open: { url in Task { await state.open(url) } }, failure: { state.errorMessage = $0 })
            .alert("작업 확인", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
                Button("확인", role: .cancel) { state.errorMessage = nil }
            } message: { Text(state.errorMessage ?? "") }
    }
    private var header: some View {
        HStack(spacing: 14) {
            AppBrand("Manga Reader", symbol: "book.closed")
            Text(state.title.isEmpty ? "나만의 만화 서재" : state.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("파일 열기", systemImage: "doc") { state.chooseBook() }
            Button("폴더 열기", systemImage: "folder") { state.chooseBook(folderOnly: true) }
            Button("이 책 번역하기", systemImage: "character.bubble.ja") { state.openInTranslator() }
                .buttonStyle(.borderedProminent).disabled(state.pages.isEmpty || state.isLoading)
            bookmarkMenu
            Button { state.reading.toggleFullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("전체화면")
        }.buttonStyle(.bordered).controlSize(.small).padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 14)
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

private struct ReaderFooter: View {
    @ObservedObject var state: ReaderState
    @ObservedObject var reading: ReadingSettings
    var body: some View {
        HStack {
            Text(state.isLoading ? "책을 여는 중…" : "\(state.pages.isEmpty ? 0 : state.index + 1) / \(state.pages.count) 페이지").monospacedDigit()
            Spacer()
            Text(reading.direction == .rightToLeft ? "← 다음 · → 이전 · Space 다음" : "→ 다음 · ← 이전 · Space 다음")
                .foregroundStyle(.secondary)
        }.font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 9).background(.bar)
    }
}

private struct ReaderBody: View {
    @ObservedObject var state: ReaderState
    @ObservedObject var reading: ReadingSettings
    var body: some View {
        HStack(spacing: 0) {
            if reading.showThumbnails { ThumbnailSidebar(pages: state.pages.map(\.url), index: state.index, select: state.select); Divider() }
            if state.pages.isEmpty {
                VStack(spacing: 18) {
                    Image(systemName: "book.pages").font(.system(size: 50, weight: .light)).foregroundStyle(.white.opacity(0.65))
                    Text("만화를 펼쳐보세요").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    Text("파일이나 폴더를 끌어놓거나 열기 버튼을 누르세요.").foregroundStyle(.white.opacity(0.6))
                    Text("ZIP · 7z · RAR · CBZ · CBR · PDF · 이미지").font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(MangaUI.canvas)
            } else { ComicPageCanvas(pages: state.pages.map(\.url), index: state.index, settings: reading, onSelect: state.select) }
        }.overlay { if state.isLoading { ProgressView().controlSize(.large).padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }
}
