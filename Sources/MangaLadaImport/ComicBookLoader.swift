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
        case .imageInFolder(let image, let folder): return try loadImage(image, in: folder)
        case .externalFile(let url):
            guard ImageFileScanner.isSupportedImage(url) else { return try await load(url) }
            return try isolatedBook(image: store.copy(url))
        case .image(let data): return try isolatedBook(image: store.save(data))
        }
    }

    private func isolatedBook(image: URL) -> ComicBook {
        ComicBook(title: "가져온 이미지", pages: [ImagePage(url: image)], initialIndex: 0, sourceURL: image)
    }

    private func loadImage(_ image: URL, in folder: URL) throws -> ComicBook {
        guard ImageFileScanner.isSupportedImage(image) else { throw ComicImportError.unsupportedFormat(image.lastPathComponent) }
        guard image.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else {
            throw ComicImportError.wrongImageFolder(image.deletingLastPathComponent().lastPathComponent)
        }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let pages = try ImageFileScanner().images(in: folder, recursive: false)
        try Task.checkCancellation()
        guard let index = pages.firstIndex(where: { $0.url.standardizedFileURL == image.standardizedFileURL }) else {
            throw ComicImportError.selectedImageMissing(image.lastPathComponent)
        }
        return ComicBook(title: folder.lastPathComponent, pages: pages, initialIndex: index, sourceURL: folder)
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
            try Task.checkCancellation()
            let target = root.appendingPathComponent(String(format: "%05d.png", number))
            if !FileManager.default.fileExists(atPath: target.path) {
                guard let page = document.page(at: number) else { throw ComicImportError.invalidPDF }
                try publishPDFPage(page, to: target)
            }
            pages.append(ImagePage(url: target))
        }
        return pages
    }

    /// A cached page exists only after a complete PNG is written; an interrupted render is never reused.
    private func publishPDFPage(_ page: CGPDFPage, to target: URL) throws {
        let partial = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial.png")
        defer { if FileManager.default.fileExists(atPath: partial.path) { try? FileManager.default.removeItem(at: partial) } }
        try writePDFPage(page, to: partial)
        do { try FileManager.default.moveItem(at: partial, to: target) }
        catch {
            // Another reader may publish the same page first; only a completed page is reused.
            guard FileManager.default.fileExists(atPath: target.path) else { throw error }
        }
    }

    private func writePDFPage(_ page: CGPDFPage, to target: URL) throws {
        let box = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { throw ComicImportError.invalidPDF }
        // The drawing transform applies the page's /Rotate; the canvas must follow it.
        let quarterTurned = abs(Int(page.rotationAngle)) % 180 == 90
        let rect = quarterTurned ? CGRect(x: 0, y: 0, width: box.height, height: box.width) : box
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
    case wrongImageFolder(String), selectedImageMissing(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let name): "열 수 없는 형식입니다: \(name)"
        case .emptyBook: "읽을 이미지가 없는 파일 또는 폴더입니다."
        case .invalidPDF: "PDF 페이지를 읽을 수 없습니다. 암호 또는 파일 상태를 확인해주세요."
        case .invalidImage: "이미지 데이터를 읽을 수 없습니다. 100MB·6,400만 픽셀 이내의 PNG·JPEG·TIFF·HEIC 등 이미지를 사용해주세요."
        case .wrongImageFolder(let name): "선택한 이미지가 있는 ‘\(name)’ 폴더를 선택해주세요. 다른 폴더의 이미지는 열지 않았습니다."
        case .selectedImageMissing(let name): "선택한 이미지 ‘\(name)’를 폴더에서 찾을 수 없습니다. 파일이 이동·삭제되었거나 숨겨져 있는지 확인해주세요."
        }
    }
}
