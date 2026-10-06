import CryptoKit
import Foundation

public struct ImageFingerprint: Sendable {
    public init() {}

    /// Streams the file so multi-gigabyte archives and PDFs are not held in memory.
    /// The digest is identical to `make(for: Data(contentsOf:))`, keeping existing cache keys.
    public func make(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4_194_304), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Self.hex(hasher.finalize())
    }

    public func make(for data: Data) -> String {
        Self.hex(SHA256.hash(data: data))
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
