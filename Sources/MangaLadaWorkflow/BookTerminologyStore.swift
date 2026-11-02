import Foundation
import MangaLadaCore

/// Separate book preferences: never writes source images, rendered output, translation caches or review drafts.
public struct BookTerminologyStore: Sendable {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func fileURL(for source: URL) -> URL {
        directory.appendingPathComponent(ComicSourceIdentity.fingerprint(for: source) + ".json")
    }
    public func load(for source: URL) throws -> TranslationGlossary {
        let file = fileURL(for: source)
        guard FileManager.default.fileExists(atPath: file.path) else { return TranslationGlossary() }
        return try JSONDecoder().decode(TranslationGlossary.self, from: Data(contentsOf: file))
    }
    public func save(_ glossary: TranslationGlossary, for source: URL) throws {
        let file = fileURL(for: source)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(glossary)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileChangeTransaction.withRollback(at: [file]) { try bytes.write(to: file, options: .atomic) }
    }
}
