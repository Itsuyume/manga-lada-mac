import Foundation

/// Owns one replaceable preview file, independent of the committed page and OCR cache.
final class LetteringPreviewFile: Sendable {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("manga-review-\(UUID()).png")

    deinit { try? FileManager.default.removeItem(at: url) }
}
