import Foundation

/// User-selected books retain folder navigation; external images are isolated snapshots.
public enum ComicInput: Sendable {
    case file(URL)
    case externalFile(URL)
    case image(Data)
}
