import Foundation

/// Books retain folder navigation; single-image imports are isolated snapshots.
public enum ComicInput: Sendable {
    case file(URL)
    /// Both URLs come from the file picker; folder access is explicit for sibling pages.
    case imageInFolder(image: URL, folder: URL)
    /// Images selected without sibling pages or supplied by other apps use the same isolated import.
    case externalFile(URL)
    case image(Data)
}
