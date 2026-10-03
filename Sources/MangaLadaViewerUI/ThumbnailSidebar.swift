import AppKit
import SwiftUI

public struct ThumbnailSidebar: View {
    let pages: [URL]
    let index: Int
    let completed: Set<Int>
    let select: (Int) -> Void
    public init(pages: [URL], index: Int, completed: Set<Int> = [], select: @escaping (Int) -> Void) {
        self.pages = pages; self.index = index; self.completed = completed; self.select = select
    }
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(pages.indices, id: \.self) { number in
                        Button { select(number) } label: {
                            VStack(spacing: 6) {
                                Thumbnail(url: pages[number]).frame(width: 92, height: 125)
                                    .background(.white).overlay { Rectangle().stroke(number == index ? MangaUI.accent : .gray.opacity(0.3), lineWidth: number == index ? 2 : 1) }
                                HStack(spacing: 4) {
                                    Text("\(number + 1)").monospacedDigit()
                                    if completed.contains(number) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }.font(.system(size: 11)).foregroundStyle(.secondary)
                            }.padding(3)
                        }.buttonStyle(.plain).id(number).accessibilityLabel("\(number + 1)페이지")
                    }
                }.padding(.vertical, 16).padding(.horizontal, 16)
            }.onChange(of: index, initial: true) { _, value in proxy.scrollTo(value) }
        }.frame(width: 138).background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: failed ? "photo.badge.exclamationmark" : "photo").foregroundStyle(.gray) }
        }.task(id: url) {
            do {
                let pixels = try await Task.detached { try PageImageLoader.load(url, maximumPixels: 240) }.value
                try Task.checkCancellation(); image = NSImage(cgImage: pixels, size: .zero)
            } catch is CancellationError { } catch { failed = true }
        }
    }
}
