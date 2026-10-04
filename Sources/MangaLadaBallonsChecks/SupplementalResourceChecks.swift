import AppKit
import Foundation
import MangaLadaBallons
import MangaLadaCore

/// Executes the real Python adapter on a solid background; no model or substitute process is used.
@MainActor
enum SupplementalResourceChecks {
    static func run(python: URL, resources: URL) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SupplementalResources-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let before = try snapshot(resources)
        try require(!before.keys.contains { $0.hasSuffix(".pyc") }, "Resource directory must start without Python caches.")
        let source = root.appendingPathComponent("source.png"), clean = root.appendingPathComponent("clean.png")
        let image = try makeImage()
        try image.write(to: source); try image.write(to: clean)
        let engine = BallonsTranslatorEngine(pythonURL: python, sourceRootURL: root, runsDirectoryURL: root)
        try await engine.eraseSupplementalText([], cleanImageURL: clean, bounded: true, maskSourceURL: source)
        try require(try Data(contentsOf: clean) == image, "Empty removal changed the image.")
        let block = TextBlock(box: TextBox(x: 0.2, y: 0.2, width: 0.6, height: 0.6), originalText: "確認")
        try await engine.eraseSupplementalText([block], cleanImageURL: clean, bounded: true, maskSourceURL: source)
        try checkImage(clean)
        do {
            try await engine.eraseSupplementalText([block], cleanImageURL: root.appendingPathComponent("missing.png"), bounded: true)
            throw Failure.failed("Missing input was silently accepted.")
        } catch let error as BallonsTranslatorEngineError {
            guard case .processFailed = error else { throw error }
        }
        try require(try Data(contentsOf: source) == image, "Source image was modified.")
        try require(try snapshot(resources) == before, "Python execution changed sealed resources or created a bytecode cache.")
        try FileManager.default.removeItem(at: root)
        print("Supplemental resource integrity passed: real erase, empty/failing input, source/artwork preserved, resource files unchanged")
    }

    private static func snapshot(_ directory: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
            let url = directory.appendingPathComponent(path)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files[path] = try Data(contentsOf: url) }
        }
        return files
    }

    private static func makeImage() throws -> Data {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 120, pixelsHigh: 120,
            bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .calibratedRGB,
            bytesPerRow: 360, bitsPerPixel: 24), let pixels = bitmap.bitmapData else { throw CocoaError(.coderInvalidValue) }
        for y in 0..<120 {
            for x in 0..<120 {
                let ink = (40..<60).contains(x) && (40..<80).contains(y) || (5..<10).contains(x) && (5..<10).contains(y)
                let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
                for channel in 0..<3 { pixels[offset + channel] = ink ? 0 : 255 }
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.coderInvalidValue) }
        return data
    }

    private static func checkImage(_ url: URL) throws {
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)), let pixels = bitmap.bitmapData else { throw CocoaError(.coderReadCorrupt) }
        try require(bitmap.pixelsWide == 120 && bitmap.pixelsHigh == 120, "Pixel dimensions changed.")
        try require(bitmap.bitsPerSample == 8 && bitmap.samplesPerPixel >= 3 && !bitmap.isPlanar
                    && !bitmap.bitmapFormat.contains(.alphaFirst), "Expected an interleaved 8-bit RGB PNG.")
        for y in 0..<120 {
            for x in 0..<120 {
                let offset = y * bitmap.bytesPerRow + x * bitmap.samplesPerPixel
                let expected: UInt8 = (5..<10).contains(x) && (5..<10).contains(y) ? 0 : 255
                try require((0..<3).allSatisfy { pixels[offset + $0] == expected }, "Glyph remained or unrelated artwork changed.")
            }
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }
    private enum Failure: LocalizedError {
        case failed(String)
        var errorDescription: String? { switch self { case .failed(let message): message } }
    }
}
