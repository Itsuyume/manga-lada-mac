import CoreGraphics
import Foundation
import ImageIO
import MangaLadaCore
import UniformTypeIdentifiers

/// Only complete, decodable page images are published or reused.
struct PDFPageCache {
    let directory: URL
    private struct PageDimensions {
        let width: Int
        let height: Int
        let points: CGSize
    }

    func load(_ document: CGPDFDocument) throws -> [ImagePage] {
        guard document.numberOfPages > 0 else { throw ComicImportError.emptyBook }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var pages: [ImagePage] = []
        for number in 1...document.numberOfPages {
            try Task.checkCancellation()
            guard let page = document.page(at: number) else { throw ComicImportError.invalidPDF }
            let size = try dimensions(of: page)
            let target = directory.appendingPathComponent(String(format: "%05d.png", number))
            if try !isReusable(target, size: size) {
                let data = try render(page, size: size)
                try Task.checkCancellation()
                try data.write(to: target, options: .atomic)
            }
            pages.append(ImagePage(url: target))
        }
        try Task.checkCancellation()
        return pages
    }

    private func dimensions(of page: CGPDFPage) throws -> PageDimensions {
        let rect = page.getBoxRect(.cropBox).intersection(page.getBoxRect(.mediaBox))
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else { throw ComicImportError.invalidPDF }
        let scale = min(4, 2400 / max(rect.width, rect.height))
        let rotated = abs(page.rotationAngle % 180) == 90
        let points = CGSize(width: rotated ? rect.height : rect.width, height: rotated ? rect.width : rect.height)
        return PageDimensions(width: max(1, Int(points.width * scale)), height: max(1, Int(points.height * scale)), points: points)
    }

    private func isReusable(_ url: URL, size: PageDimensions) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard PNGCacheValidation.isComplete(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetCount(source) == 1,
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        return image.width == size.width && image.height == size.height
    }

    private func render(_ page: CGPDFPage, size: PageDimensions) throws -> Data {
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: size.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ComicImportError.invalidPDF }
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        // The Quartz drawing transform only scales down. Apply raster resolution separately.
        context.scaleBy(x: CGFloat(size.width) / size.points.width, y: CGFloat(size.height) / size.points.height)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size.points), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw ComicImportError.invalidPDF }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw ComicImportError.invalidPDF }
        return data as Data
    }
}
