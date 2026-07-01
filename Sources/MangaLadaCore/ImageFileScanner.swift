import Foundation

public struct ImageFileScanner {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "png", "webp", "tif", "tiff", "bmp", "gif"
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func imagesInSameFolder(as imageURL: URL) throws -> [ImagePage] {
        let folderURL = imageURL.deletingLastPathComponent()
        return try images(in: folderURL, recursive: false)
    }

    public func images(in folderURL: URL, recursive: Bool) throws -> [ImagePage] {
        let imageURLs = recursive
            ? try recursiveImages(in: folderURL)
            : try directImages(in: folderURL)

        return imageURLs
            .sorted { lhs, rhs in
                relativePath(for: lhs, under: folderURL)
                    .localizedStandardCompare(relativePath(for: rhs, under: folderURL)) == .orderedAscending
            }
            .map(ImagePage.init(url:))
    }

    public static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private func directImages(in folderURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter(Self.isSupportedImage)
    }

    private func recursiveImages(in folderURL: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ImageFileScannerError.folderEnumerationFailed(folderURL)
        }

        var imageURLs: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains("__MACOSX") {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, Self.isSupportedImage(fileURL) else {
                continue
            }
            imageURLs.append(fileURL)
        }
        return imageURLs
    }

    private func relativePath(for fileURL: URL, under folderURL: URL) -> String {
        let basePath = folderURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(basePath) else {
            return fileURL.lastPathComponent
        }
        return String(filePath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

public enum ImageFileScannerError: LocalizedError, Equatable {
    case folderEnumerationFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .folderEnumerationFailed(let url):
            return "이미지 폴더를 훑을 수 없습니다: \(url.lastPathComponent)"
        }
    }
}
