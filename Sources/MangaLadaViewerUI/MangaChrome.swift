import SwiftUI

public extension MangaUI {
    /// Accent for text and marks drawn directly on the dark canvas.
    static let accentOnCanvas = Color(red: 0.50, green: 0.64, blue: 0.92)
    static let success = Color(red: 0.18, green: 0.62, blue: 0.36)
    static let failure = Color(red: 0.84, green: 0.27, blue: 0.24)
    static let attention = Color(red: 0.86, green: 0.53, blue: 0.16)
}

public extension View {
    /// A compact control group that sits on the canvas. Callers lay it out beside the page,
    /// never over it, so region numbers and drags on the page stay reachable.
    func mangaFloatingBar() -> some View {
        padding(.horizontal, 6).padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white.opacity(0.08)) }
            .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
    }
}

/// Shared by both apps' toolbars; the thumbnail state lives in `ReadingSettings`.
public struct ThumbnailToggleButton: View {
    @ObservedObject var settings: ReadingSettings
    public init(settings: ReadingSettings) { self.settings = settings }
    public var body: some View {
        Button { settings.showThumbnails.toggle() } label: { Image(systemName: "sidebar.left") }
            .help(settings.showThumbnails ? "썸네일 숨기기" : "썸네일 표시")
            .accessibilityLabel("썸네일 표시 / 숨기기")
    }
}
