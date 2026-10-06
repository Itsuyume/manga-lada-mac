import SwiftUI

/// Page state shown on a thumbnail. Each state differs in symbol as well as colour.
public enum ThumbnailBadge: Sendable {
    case completed, processing, failed, needsReview
    var label: String {
        switch self {
        case .completed: "완료"
        case .processing: "처리 중"
        case .failed: "실패"
        case .needsReview: "검수 필요"
        }
    }
}

public struct ThumbnailSidebar: View {
    let pages: [URL]
    let index: Int
    let badges: [Int: ThumbnailBadge]
    let select: (Int) -> Void
    public init(pages: [URL], index: Int, badges: [Int: ThumbnailBadge] = [:], select: @escaping (Int) -> Void) {
        self.pages = pages; self.index = index; self.badges = badges; self.select = select
    }
    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(pages.indices, id: \.self) { number in
                        Button { select(number) } label: {
                            VStack(spacing: 7) {
                                Thumbnail(url: pages[number]).frame(width: 92, height: 125)
                                    .background(.white)
                                    .overlay { Rectangle().stroke(number == index ? MangaUI.accent : .gray.opacity(0.3), lineWidth: number == index ? 2 : 1) }
                                    .shadow(color: number == index ? MangaUI.accent.opacity(0.35) : .clear, radius: 5)
                                    .overlay(alignment: .bottomTrailing) {
                                        if let badge = badges[number] { ThumbnailBadgeView(badge: badge).offset(x: 6, y: 6) }
                                    }
                                Text("\(number + 1)").monospacedDigit().font(.system(size: 11, weight: number == index ? .semibold : .regular))
                                    .foregroundStyle(number == index ? .primary : .secondary)
                            }.padding(3)
                        }.buttonStyle(.plain).id(number)
                            .accessibilityLabel("\(number + 1)페이지" + (badges[number].map { " · " + $0.label } ?? ""))
                    }
                }.padding(.vertical, 16).padding(.horizontal, 16)
            }.onChange(of: index, initial: true) { _, value in proxy.scrollTo(value) }
        }.frame(width: 138).background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ThumbnailBadgeView: View {
    let badge: ThumbnailBadge
    var body: some View {
        Group {
            switch badge {
            case .processing: ProgressView().controlSize(.mini)
            case .completed: symbol("checkmark.circle.fill", MangaUI.success)
            case .failed: symbol("exclamationmark.circle.fill", MangaUI.failure)
            case .needsReview: symbol("pencil.circle.fill", MangaUI.attention)
            }
        }
        .frame(width: 20, height: 20)
        .background(Color(nsColor: .controlBackgroundColor), in: Circle())
        .help(badge.label)
    }
    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 17)).symbolRenderingMode(.palette).foregroundStyle(.white, color)
    }
}

private struct Thumbnail: View {
    let url: URL
    @StateObject private var resource = PageImageState()
    var body: some View {
        Group {
            if let image = resource.image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Image(systemName: resource.failure == nil ? "photo" : "photo.badge.exclamationmark").foregroundStyle(.gray) }
        }.task(id: url) { await resource.load(url, maximumPixels: 240) }
            .onDisappear { resource.release() }
    }
}
