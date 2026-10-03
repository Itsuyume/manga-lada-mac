import CoreGraphics
import Foundation
import ImageIO
import MangaLadaCore
import UniformTypeIdentifiers

public struct ComicBook: Sendable {
    public let title: String
    public let pages: [ImagePage]
    public let initialIndex: Int
    public let sourceURL: URL
}

public actor ComicBookLoader {
    private let extractionRoot: URL
    public init(extractionRoot: URL) { self.extractionRoot = extractionRoot }

    public func load(_ url: URL) async throws -> ComicBook {
        try Task.checkCancellation()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try loadSynchronously(url)
    }

    public func load(_ input: ComicInput) async throws -> ComicBook {
        try Task.checkCancellation()
        let store = ImportedImageStore(root: extractionRoot.appendingPathComponent("ImportedImages"))
        switch input {
        case .file(let url): return try await load(url)
        case .externalFile(let url):
            guard ImageFileScanner.isSupportedImage(url) else { return try await load(url) }
            return try isolatedBook(image: store.copy(url))
        case .image(let data): return try isolatedBook(image: store.save(data))
        }
    }

    private func isolatedBook(image: URL) -> ComicBook {
        ComicBook(title: "가져온 이미지", pages: [ImagePage(url: image)], initialIndex: 0, sourceURL: image)
    }

    private func loadSynchronously(_ url: URL) throws -> ComicBook {
        let scanner = ImageFileScanner()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        let pages: [ImagePage]
        if values.isDirectory == true { pages = try scanner.images(in: url, recursive: true) }
        else if ArchiveExtractor.isSupportedArchive(url) {
            pages = try scanner.images(in: ArchiveExtractor(extractionRoot: extractionRoot).extract(url), recursive: true)
        } else if url.pathExtension.lowercased() == "pdf" { pages = try renderPDF(url) }
        else if ImageFileScanner.isSupportedImage(url) { pages = try scanner.imagesInSameFolder(as: url) }
        else { throw ComicImportError.unsupportedFormat(url.lastPathComponent) }
        guard !pages.isEmpty else { throw ComicImportError.emptyBook }
        let imageFile = values.isDirectory != true && ImageFileScanner.isSupportedImage(url)
        let canonicalURL = imageFile ? url.deletingLastPathComponent() : url
        let title = values.isDirectory == true || imageFile ? canonicalURL.lastPathComponent : url.deletingPathExtension().lastPathComponent
        return ComicBook(title: title, pages: pages,
                         initialIndex: pages.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) ?? 0, sourceURL: canonicalURL)
    }

    private func renderPDF(_ url: URL) throws -> [ImagePage] {
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted || document.isUnlocked else { throw ComicImportError.invalidPDF }
        let root = extractionRoot.appendingPathComponent("pdf-\(try ImageFingerprint().make(for: url))")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var pages: [ImagePage] = []
        for number in 1...max(1, document.numberOfPages) {
            let target = root.appendingPathComponent(String(format: "%05d.png", number))
            if !FileManager.default.fileExists(atPath: target.path) {
                guard let page = document.page(at: number) else { throw ComicImportError.invalidPDF }
                try writePDFPage(page, to: target)
            }
            pages.append(ImagePage(url: target))
        }
        return pages
    }

    private func writePDFPage(_ page: CGPDFPage, to target: URL) throws {
        let rect = page.getBoxRect(.cropBox)
        guard rect.width > 0, rect.height > 0 else { throw ComicImportError.invalidPDF }
        let scale = min(4, 2400 / max(rect.width, rect.height))
        let width = max(1, Int(rect.width * scale)), height = max(1, Int(rect.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ComicImportError.invalidPDF }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let targetRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: targetRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage(), let writer = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw ComicImportError.invalidPDF }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw ComicImportError.invalidPDF }
    }
}

public enum ComicImportError: LocalizedError {
    case unsupportedFormat(String), emptyBook, invalidPDF, invalidImage
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name): "열 수 없는 형식입니다: \(name)"
        case .emptyBook: "읽을 이미지가 없는 파일 또는 폴더입니다."
        case .invalidPDF: "PDF 페이지를 읽을 수 없습니다. 암호 또는 파일 상태를 확인해주세요."
        case .invalidImage: "이미지 데이터를 읽을 수 없습니다. 100MB·6,400만 픽셀 이내의 PNG·JPEG·TIFF·HEIC 등 이미지를 사용해주세요."
        }
    }
}
