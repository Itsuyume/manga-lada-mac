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

    /// Longest side a single decoded page may reach, within common GPU texture limits.
    static let longestSideLimit = 16_384

    private static func decode(_ url: URL, maximumPixels: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.lastPathComponent])
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: longestSide(of: source, maximumPixels: maximumPixels)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.lastPathComponent])
        }
        return image
    }

    /// `maximumPixels` bounds the longest side of ordinary pages. A long strip keeps the same
    /// pixel budget (maximumPixels²) instead, so its narrow side stays readable without
    /// decoding more pixels than a square page at the same limit.
    static func longestSide(width: Int, height: Int, maximumPixels: Int) -> Int {
        let short = min(width, height), long = max(width, height)
        guard short > 0, maximumPixels > 0 else { return maximumPixels }
        let budgeted = (maximumPixels * maximumPixels) / short
        return max(maximumPixels, min(long, budgeted, longestSideLimit))
    }

    private static func longestSide(of source: CGImageSource, maximumPixels: Int) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return maximumPixels }
        return longestSide(width: width, height: height, maximumPixels: maximumPixels)
    }
}
