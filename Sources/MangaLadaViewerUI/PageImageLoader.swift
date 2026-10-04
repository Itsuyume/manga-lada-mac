import Foundation
import ImageIO

enum PageImageLoader {
    static func load(_ url: URL, maximumPixels: Int) async throws -> CGImage {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let image = try decode(url, maximumPixels: maximumPixels)
            try Task.checkCancellation()
            return image
        }
        return try await withTaskCancellationHandler {
            let image = try await worker.value
            try Task.checkCancellation()
            return image
        } onCancel: { worker.cancel() }
    }

    private static func decode(_ url: URL, maximumPixels: Int) throws -> CGImage {
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
