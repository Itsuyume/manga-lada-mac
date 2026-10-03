import CryptoKit
import Foundation

public struct ImageFingerprint: Sendable {
    public init() {}

    public func make(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        return make(for: data)
    }

    public func make(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
