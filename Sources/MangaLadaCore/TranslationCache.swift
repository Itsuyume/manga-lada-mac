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

    /// Newest entry whose fingerprint satisfies `matches`. Only file names are listed until a
    /// match is found. A sibling that cannot be decoded is passed over for an older readable one;
    /// an explicitly requested key still reports its decoding error through `load`.
    public func newestEntry(where matches: (String) -> Bool) throws -> PageTranslation? {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return nil }
        let candidates = try fileManager.contentsOfDirectory(atPath: cacheDirectory.path).compactMap { name -> (URL, Date)? in
            guard name.hasSuffix(".json"), matches(String(name.dropLast(5))) else { return nil }
            let url = cacheDirectory.appendingPathComponent(name)
            let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return (url, modified ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        for (url, _) in candidates {
            do { return try decoder.decode(PageTranslation.self, from: Data(contentsOf: url)) }
            catch is DecodingError { continue }
        }
        return nil
    }

    /// Moves an unreadable entry aside so a forced rebuild can proceed. Nothing is deleted.
    public func quarantine(fingerprint: String) throws {
        let url = cacheFileURL(fingerprint: fingerprint)
        guard fileManager.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let target = cacheDirectory.appendingPathComponent("\(fingerprint).unreadable-\(stamp)-\(UUID().uuidString.prefix(8))")
        try fileManager.moveItem(at: url, to: target)
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
