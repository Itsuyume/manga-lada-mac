import Foundation

public enum TranslationCacheError: Error, Equatable {
    case invalidCacheDirectory(URL)
}

public struct TranslationCache {
    private let cacheDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(cacheDirectory: URL, fileManager: FileManager = .default) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load(fingerprint: String) throws -> PageTranslation? {
        let url = cacheFileURL(fingerprint: fingerprint)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(PageTranslation.self, from: data)
    }

    public func save(_ translation: PageTranslation) throws {
        try ensureDirectory()
        let data = try encoder.encode(translation)
        try data.write(to: cacheFileURL(fingerprint: translation.imageFingerprint), options: .atomic)
    }

    public func delete(fingerprint: String) throws {
        let url = cacheFileURL(fingerprint: fingerprint)
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    public func cacheFileURL(fingerprint: String) -> URL {
        cacheDirectory.appendingPathComponent("\(fingerprint).json")
    }

    private func ensureDirectory() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: cacheDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw TranslationCacheError.invalidCacheDirectory(cacheDirectory)
            }
            return
        }

        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
