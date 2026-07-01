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
        let folderContents = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return folderContents
            .filter(Self.isSupportedImage)
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
            .map(ImagePage.init(url:))
    }

    public static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
