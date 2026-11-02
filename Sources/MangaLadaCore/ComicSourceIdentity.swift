import Foundation

/// Stable preferences for a source book, independent of a page's processing/cache versions.
public enum ComicSourceIdentity {
    public static func fingerprint(for source: URL) -> String {
        ImageFingerprint().make(for: Data(source.standardizedFileURL.path.utf8))
    }
}
