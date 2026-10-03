import Foundation
import MangaLadaCore

public struct TranslationBook: Sendable {
    public let directory: URL
    public let pageCount: Int
    public var manifest: TranslationBookManifest
    public func pageURL(at index: Int) -> URL { directory.appendingPathComponent(String(format: "%05d.png", index + 1)) }
}

public struct TranslationBookManifest: Codable, Sendable {
    public let version: Int
    public let title: String
    public let inputFingerprint: String
    public let pageCount: Int
    public var completedPages: [Int]
    public var failures: [Int: String]
}

public struct TranslationBookStore: Sendable {
    public init() {}
    public func prepare(sourceURL: URL, title: String, pages: [ImagePage], outputRoot: URL) throws -> TranslationBook {
        guard !pages.isEmpty else { throw BookOutputError.emptyBook }
        let inputKey = try fingerprint(sourceURL, pages: pages)
        let safeTitle = title.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "_").prefix(100)
        let baseName = (safeTitle.isEmpty ? "만화" : String(safeTitle)) + "_한국어"
        var directory = outputRoot.appendingPathComponent(baseName, isDirectory: true)
        for attempt in 0..<1_000 {
            let marker = directory.appendingPathComponent(ImageFileScanner.generatedBookMarker)
            if FileManager.default.fileExists(atPath: marker.path) {
                let stored = try JSONDecoder().decode(TranslationBookManifest.self, from: Data(contentsOf: marker))
                if stored.inputFingerprint == inputKey { return TranslationBook(directory: directory, pageCount: pages.count, manifest: stored) }
            } else if !FileManager.default.fileExists(atPath: directory.path) {
                return try create(directory: directory, title: title, inputKey: inputKey, pageCount: pages.count)
            }
            directory = outputRoot.appendingPathComponent("\(baseName)_\(attempt + 2)", isDirectory: true)
        }
        throw BookOutputError.tooManyFolders
    }
    public func save(_ book: TranslationBook) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(book.manifest).write(to: book.directory.appendingPathComponent(ImageFileScanner.generatedBookMarker), options: .atomic)
    }
    private func create(directory: URL, title: String, inputKey: String, pageCount: Int) throws -> TranslationBook {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = TranslationBookManifest(version: 1, title: title, inputFingerprint: inputKey, pageCount: pageCount, completedPages: [], failures: [:])
        let book = TranslationBook(directory: directory, pageCount: pageCount, manifest: manifest)
        try save(book); return book
    }
    private func fingerprint(_ source: URL, pages: [ImagePage]) throws -> String {
        var records = [source.standardizedFileURL.path]
        for page in pages {
            let values = try page.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            records.append("\(page.url.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return ImageFingerprint().make(for: Data(records.joined(separator: "\n").utf8))
    }
}

public enum BookOutputError: LocalizedError {
    case emptyBook, tooManyFolders
    public var errorDescription: String? {
        switch self { case .emptyBook: "저장할 페이지가 없습니다."; case .tooManyFolders: "같은 이름의 결과 폴더가 너무 많습니다. 다른 저장 폴더를 지정해주세요." }
    }
}
