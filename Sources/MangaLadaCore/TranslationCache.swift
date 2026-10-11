import Foundation

public enum TranslationCacheError: Error, Equatable {
    case invalidCacheDirectory(URL)
    case invalidPointer
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

    /// Records which entry holds a page's newest translation under a context-independent name, so a
    /// changed neighbouring page (or a different translation order) finds the reviewed page again.
    public func savePointer(_ name: String, to fingerprint: String) throws {
        guard Self.isValidName(name), Self.isValidName(fingerprint) else { throw TranslationCacheError.invalidPointer }
        try ensureDirectory()
        try Data(fingerprint.utf8).write(to: pointerURL(name), options: .atomic)
    }

    /// The entry a pointer names, or nil when there is no usable pointer or its entry no longer exists.
    /// A pointer is only a lookup hint; the entry it names is decoded with the usual error reporting.
    public func loadPointer(_ name: String) throws -> PageTranslation? {
        guard let target = pointerTarget(name) else { return nil }
        return try load(fingerprint: target)
    }

    public func pointerTarget(_ name: String) -> String? {
        guard Self.isValidName(name), let data = fileManager.contents(atPath: pointerURL(name).path) else { return nil }
        let target = String(decoding: data, as: UTF8.self)
        return Self.isValidName(target) ? target : nil
    }

    private func pointerURL(_ name: String) -> URL { cacheDirectory.appendingPathComponent("\(name).pointer") }
    private static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 512 && !name.contains("/") && !name.hasPrefix(".") && !name.contains(where: \.isNewline)
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
