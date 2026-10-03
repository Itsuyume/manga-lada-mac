import Foundation

public struct ArchiveExtractor: Sendable {
    public static let supportedExtensions: Set<String> = ["zip", "cbz", "7z", "cb7", "rar", "cbr", "tar", "tgz", "gz", "tbz", "tbz2", "bz2", "txz", "xz"]
    private let extractionRoot: URL
    public init(extractionRoot: URL) { self.extractionRoot = extractionRoot }

    public func extract(_ archiveURL: URL) throws -> URL {
        guard Self.isSupportedArchive(archiveURL) else { throw ArchiveExtractionError.unsupportedArchive(archiveURL) }
        let digest = try ImageFingerprint().make(for: archiveURL)
        let root = extractionRoot.appendingPathComponent("libarchive-v2", isDirectory: true)
        let destination = root.appendingPathComponent(digest, isDirectory: true)
        let marker = destination.appendingPathComponent(".manga-lada-extracted")
        if FileManager.default.fileExists(atPath: marker.path) { return destination }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent("\(digest)-\(UUID().uuidString).partial", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { if FileManager.default.fileExists(atPath: staging.path) { try? FileManager.default.removeItem(at: staging) } }
        let listing = try run(["-tf", archiveURL.path], archiveURL: archiveURL)
        for path in listing.split(separator: "\n") {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                throw ArchiveExtractionError.unsafeEntry(String(path))
            }
        }
        _ = try run(["-xf", archiveURL.path, "-C", staging.path], archiveURL: archiveURL)
        try rejectSymbolicLinks(in: staging)
        try Data().write(to: staging.appendingPathComponent(".manga-lada-extracted"))
        do { try FileManager.default.moveItem(at: staging, to: destination) }
        catch {
            // Another app can win the atomic publish. Only reuse a completed extraction.
            guard FileManager.default.fileExists(atPath: marker.path) else { throw error }
        }
        return destination
    }

    public static func isSupportedArchive(_ url: URL) -> Bool { supportedExtensions.contains(url.pathExtension.lowercased()) }

    private func run(_ arguments: [String], archiveURL: URL) throws -> String {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let output = try String(contentsOf: log, encoding: .utf8)
        guard process.terminationStatus == 0 else {
            throw ArchiveExtractionError.extractionFailed(archiveURL, exitCode: process.terminationStatus, message: String(output.suffix(1600)))
        }
        return output
    }

    private func rejectSymbolicLinks(in directory: URL) throws {
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) else {
            throw ArchiveExtractionError.unsafeEntry(directory.lastPathComponent)
        }
        for case let url as URL in entries {
            if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw ArchiveExtractionError.unsafeEntry(url.lastPathComponent)
            }
        }
    }
}

public enum ArchiveExtractionError: LocalizedError, Equatable {
    case unsupportedArchive(URL)
    case extractionFailed(URL, exitCode: Int32, message: String)
    case unsafeEntry(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedArchive(let url): "지원하지 않는 압축 파일입니다: \(url.lastPathComponent)"
        case .extractionFailed(let url, let code, let message): "압축 해제에 실패했습니다: \(url.lastPathComponent) (exit \(code)) \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .unsafeEntry(let entry): "압축 파일에 안전하게 열 수 없는 경로가 있습니다: \(entry)"
        }
    }
}
