import AppKit
import ImageIO
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
    @State private var image: NSImage?
    @State private var failure: String?

    var body: some View {
        Group {
            if let image {
                let size = fittedSize(image.size)
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: size.width, height: size.height)
                    .background(.white).shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                    .accessibilityLabel(url.lastPathComponent)
                    .overlay { if let selection { ComicImageSelectionOverlay(selection: selection.wrappedValue, size: size) } }
                    .overlay { if !regions.isEmpty {
                        ComicRegionMarkers(blocks: regions, size: size, selectedID: selectedRegionID, selection: selection?.wrappedValue)
                    } }
                    .contentShape(Rectangle())
                    .simultaneousGesture(selectionGesture(in: size), including: selection == nil ? .none : .all)
            } else if let failure {
                ContentUnavailableView("이미지를 읽을 수 없습니다", systemImage: "photo.badge.exclamationmark", description: Text(failure))
                    .frame(width: min(260, maximumSize.width), height: min(200, maximumSize.height))
            } else { ProgressView().frame(width: max(1, maximumSize.width), height: max(1, maximumSize.height)) }
        }
        .task(id: "\(url.path)-\(revision)") { await load() }
    }

    private func selectionGesture(in size: CGSize) -> some Gesture {
        // Own dragging above both overlays so region badges do not cover its hit area.
        DragGesture(minimumDistance: 3).onChanged { value in
            selection?.wrappedValue = ImageRegionSelection.box(from: value.startLocation, to: value.location, in: size)
        }.onEnded { value in
            selection?.wrappedValue = ImageRegionSelection.box(from: value.startLocation, to: value.location, in: size)
        }
    }

    private func fittedSize(_ source: NSSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return .zero }
        let widthScale = maximumSize.width / source.width
        let scale = (fitWidth ? widthScale : min(widthScale, maximumSize.height / source.height)) * zoom
        return CGSize(width: max(1, source.width * scale), height: max(1, source.height * scale))
    }

    private func load() async {
        do {
            let pixels = try await Task.detached(priority: .userInitiated) { try PageImageLoader.load(url, maximumPixels: 4096) }.value
            try Task.checkCancellation()
            image = NSImage(cgImage: pixels, size: .zero); failure = nil
        } catch is CancellationError { } catch { failure = error.localizedDescription }
    }
}

enum PageImageLoader {
    static func load(_ url: URL, maximumPixels: Int) throws -> CGImage {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: maximumPixels]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.lastPathComponent])
        }
        return image
    }
}
