import AppKit
import Combine

@MainActor
final class PageImageState: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var sourceSize: CGSize?
    @Published private(set) var failure: String?
    private var sourceURL: URL?
    private var loadID = UUID()

    func load(_ url: URL, maximumPixels: Int) async {
        let id = UUID()
        loadID = id
        if sourceURL != url { sourceSize = nil }
        sourceURL = url
        image = nil
        failure = nil
        do {
            let pixels = try await PageImageLoader.load(url, maximumPixels: maximumPixels)
            guard loadID == id, !Task.isCancelled else { return }
            sourceSize = CGSize(width: pixels.width, height: pixels.height)
            image = NSImage(cgImage: pixels, size: .zero)
        } catch {
            guard loadID == id, !Task.isCancelled, !(error is CancellationError) else { return }
            failure = error.localizedDescription
        }
    }

    func release() {
        loadID = UUID()
        image = nil
        // Keep the aspect ratio so LazyVStack retains the row's height while it reloads.
    }
}
