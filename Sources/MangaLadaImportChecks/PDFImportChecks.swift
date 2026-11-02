import CoreGraphics
import Foundation
import ImageIO
import MangaLadaCore
import MangaLadaImport

enum PDFImportChecks {
    static func run(root: URL, sampleImage: URL) async throws {
        try await checkCache(root: root, sampleImage: sampleImage)
        try await checkCancellation(root: root)
        try await checkRotation(root: root)
        print("PDF checks passed: decoded cache reuse, damaged/wrong-size repair, cancellation, atomic pages, resume and source preservation")
    }

    private static func checkCache(root: URL, sampleImage: URL) async throws {
        let source = root.appendingPathComponent("cache.pdf")
        try writePDF(source, count: 2)
        let original = try Data(contentsOf: source)
        let cache = root.appendingPathComponent("pdf-cache-check")
        let loader = ComicBookLoader(extractionRoot: cache)
        let book = try await loader.load(source)
        try check(book.pages.count == 2 && book.pages.allSatisfy { isValid($0.url) }, "Initial PDF pages did not decode.")
        let first = book.pages[0].url, second = book.pages[1].url
        let bytes = try Data(contentsOf: first)
        let timestamp = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: second.path)
        try Data(bytes.prefix(bytes.count / 2)).write(to: first)
        _ = try await loader.load(source)
        let repaired = try Data(contentsOf: first)
        try check(repaired == bytes && isValid(first), "Truncated PNG repair mismatch: before=\(bytes.count), after=\(repaired.count), decoded=\(isValid(first)).")
        guard let payload = bytes.range(of: Data("IDAT".utf8)) else { throw Failure.failed("PDF fixture did not contain image data.") }
        let length = bytes[(payload.lowerBound - 4)..<payload.lowerBound].reduce(0) { $0 << 8 | Int($1) }
        var wrongChecksum = bytes; wrongChecksum[payload.upperBound + length] ^= 1
        try wrongChecksum.write(to: first)
        _ = try await loader.load(source)
        try check(try Data(contentsOf: first) == bytes, "A PNG with a damaged data checksum was reused.")
        try Data(contentsOf: sampleImage).write(to: first)
        _ = try await loader.load(source)
        try check(try Data(contentsOf: first) == bytes, "A valid PNG with incorrect page dimensions was reused.")
        let attributes = try FileManager.default.attributesOfItem(atPath: second.path)
        try check(attributes[.modificationDate] as? Date == timestamp, "A valid untouched PDF cache page was rewritten.")
        try check(try Data(contentsOf: source) == original, "Cache repair modified the source PDF.")
        try FileManager.default.removeItem(at: first)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
        let note = first.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: note)
        do { _ = try await loader.load(source); throw Failure.failed("A directory at the cache page path was accepted.") }
        catch is CocoaError { }
        try check(try Data(contentsOf: note) == Data("keep".utf8), "Cache repair removed an unexpected directory.")
        let shared = root.appendingPathComponent("concurrent-pdf-cache")
        async let left = ComicBookLoader(extractionRoot: shared).load(source)
        async let right = ComicBookLoader(extractionRoot: shared).load(source)
        let pair = try await (left, right)
        try check(pair.0.pages == pair.1.pages && pair.0.pages.allSatisfy { isValid($0.url) }, "Concurrent PDF imports published a partial PNG.")
    }

    private static func checkCancellation(root: URL) async throws {
        let source = root.appendingPathComponent("cancel.pdf")
        try writePDF(source, count: 80)
        let original = try Data(contentsOf: source)
        let cache = root.appendingPathComponent("cancel-pdf-cache")
        let loader = ComicBookLoader(extractionRoot: cache)
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await loader.load(source)
        }
        do { _ = try await before.value; throw Failure.failed("An already-cancelled PDF load succeeded.") }
        catch is CancellationError { }
        try check(!FileManager.default.fileExists(atPath: cache.path), "An already-cancelled load created a cache.")
        let load = Task { try await loader.load(source) }
        let monitor = Task.detached {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: cache.path) {
                    let folders = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
                    if folders.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("00001.png").path) }) {
                        load.cancel(); return
                    }
                }
                try await Task.sleep(for: .milliseconds(1))
            }
            load.cancel(); throw Failure.failed("The PDF cancellation monitor did not observe a published page.")
        }
        do { _ = try await load.value; throw Failure.failed("Cancelling PDF rendering returned a completed book.") }
        catch is CancellationError { }
        try await monitor.value
        let directories = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        let published = try directories.flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
        try check(!published.isEmpty && published.count < 80 && published.allSatisfy { isValid($0) }, "Cancelled PDF rendering left incomplete cache pages or rendered every page.")
        let resumed = try await loader.load(source)
        try check(resumed.pages.count == 80 && resumed.pages.allSatisfy { isValid($0.url) }, "A cancelled PDF could not be resumed.")
        try check(try Data(contentsOf: source) == original, "Cancelling PDF rendering modified its source.")
    }

    private static func writePDF(_ url: URL, count: Int) throws {
        var rect = CGRect(x: 0, y: 0, width: 100, height: 150)
        guard let consumer = CGDataConsumer(url: url as CFURL), let context = CGContext(consumer: consumer, mediaBox: &rect, nil) else {
            throw Failure.failed("Cannot create a PDF fixture.")
        }
        for _ in 0..<count { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
    }

    private static func checkRotation(root: URL) async throws {
        let source = root.appendingPathComponent("rotated.pdf")
        let paint = "1 0 0 rg\n0 0 100 150 re f\n"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 150] /Rotate 90 /Resources << >> /Contents 4 0 R >>",
                       "<< /Length \(paint.utf8.count) >>\nstream\n\(paint)endstream"]
        var data = Data("%PDF-1.4\n".utf8), offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(data.count); data.append(Data("\(index + 1) 0 obj\n\(object)\nendobj\n".utf8))
        }
        let xref = data.count
        data.append(Data("xref\n0 5\n0000000000 65535 f \n".utf8))
        for offset in offsets { data.append(Data(String(format: "%010d 00000 n \n", offset).utf8)) }
        data.append(Data("trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8))
        try data.write(to: source)
        let book = try await ComicBookLoader(extractionRoot: root.appendingPathComponent("rotated-cache")).load(source)
        guard let imageSource = CGImageSourceCreateWithURL(book.pages[0].url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil), image.width == 600, image.height == 400,
              let context = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 2400,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = context.data else { throw Failure.failed("Rotated PDF used unrotated page dimensions.") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 600, height: 400))
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        for (x, y) in [(1, 1), (598, 1), (1, 398), (598, 398)] {
            let offset = y * 2400 + x * 4
            try check(bytes[offset] > 240 && bytes[offset + 1] < 15 && bytes[offset + 2] < 15,
                      "Rotated PDF paint at \(x),\(y): \(bytes[offset]),\(bytes[offset + 1]),\(bytes[offset + 2]),\(bytes[offset + 3]).")
        }
    }

    private static func isValid(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return false }
        return image.width == 400 && image.height == 600 && CGImageSourceGetStatus(source) == .statusComplete
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.failed(message) } }
    private enum Failure: Error { case failed(String) }
}
