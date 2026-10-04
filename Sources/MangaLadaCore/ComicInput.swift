import Foundation

/// User-selected books retain folder navigation; external images are isolated snapshots.
public enum ComicInput: Sendable {
    case file(URL)
    /// Both URLs come from the file picker; folder access is explicit for sibling pages.
    case imageInFolder(image: URL, folder: URL)
    case externalFile(URL)
    case image(Data)
}
