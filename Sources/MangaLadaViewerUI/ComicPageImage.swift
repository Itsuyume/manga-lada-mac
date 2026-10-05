import AppKit
import MangaLadaCore
import SwiftUI

struct ComicPageImage: View {
    let url: URL
    let maximumSize: CGSize
    let fitWidth: Bool
    let zoom: Double
    let revision: Int
    var selection: Binding<TextBox?>?
    var regions: [TextBlock] = []
    var selectedRegionID: Binding<UUID?>?
    var onMoveRegion: ((UUID, CGSize) -> Void)?
    var useLetteringCoordinates = false
    @StateObject private var resource = PageImageState()

    var body: some View {
        Group {
            if let image = resource.image {
                let size = placeholderSize
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .background(.white).shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                    .accessibilityLabel(url.lastPathComponent)
                    .overlay { if let selection { ComicImageSelectionOverlay(selection: selection.wrappedValue, size: size) } }
                    .overlay { if !regions.isEmpty {
                        ComicRegionMarkers(blocks: regions, size: size, selectedID: selectedRegionID,
                                           selection: selection?.wrappedValue, onMove: selection == nil ? onMoveRegion : nil,
                                           useLetteringCoordinates: useLetteringCoordinates)
                    } }
                    .contentShape(Rectangle())
                    // Keep the region markers interactive when rectangle selection is inactive.
                    .simultaneousGesture(selectionGesture(in: size), including: selection == nil ? .subviews : .all)
            } else if let failure = resource.failure {
                ContentUnavailableView("이미지를 읽을 수 없습니다", systemImage: "photo.badge.exclamationmark", description: Text(failure))
                    .frame(width: placeholderSize.width, height: placeholderSize.height)
            } else { ProgressView().frame(width: placeholderSize.width, height: placeholderSize.height) }
        }
        .task(id: "\(url.path)-\(revision)") { await resource.load(url, maximumPixels: 4096) }
        .onDisappear { resource.release() }
    }

    private func selectionGesture(in size: CGSize) -> some Gesture {
        // Own dragging above both overlays so region badges do not cover its hit area.
        DragGesture(minimumDistance: 3).onChanged { value in
            selection?.wrappedValue = ImageRegionSelection.box(from: value.startLocation, to: value.location, in: size)
        }.onEnded { value in
            selection?.wrappedValue = ImageRegionSelection.box(from: value.startLocation, to: value.location, in: size)
        }
    }

    private var placeholderSize: CGSize {
        guard let source = resource.sourceSize else {
            return CGSize(width: max(1, maximumSize.width), height: max(1, maximumSize.height))
        }
        guard source.width > 0, source.height > 0 else { return .zero }
        let widthScale = maximumSize.width / source.width
        let scale = (fitWidth ? widthScale : min(widthScale, maximumSize.height / source.height)) * zoom
        return CGSize(width: max(1, source.width * scale), height: max(1, source.height * scale))
    }

}
