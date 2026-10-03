import Foundation
import ImageIO
import MangaLadaCore
import UniformTypeIdentifiers

/// Materializes only the image the user supplied, without enumerating another app's container.
struct ImportedImageStore {
    let root: URL

    func copy(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try save(Data(contentsOf: url))
    }

    func save(_ data: Data) throws -> URL {
        guard !data.isEmpty, data.count <= 100_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let type = CGImageSourceGetType(source), let suffix = UTType(type as String)?.preferredFilenameExtension,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 64_000_000 / height else { throw ComicImportError.invalidImage }
        let directory = root.appendingPathComponent(ImageFingerprint().make(for: data))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("00001." + suffix)
        if !FileManager.default.fileExists(atPath: target.path) { try data.write(to: target, options: .atomic) }
        return target
    }
}
