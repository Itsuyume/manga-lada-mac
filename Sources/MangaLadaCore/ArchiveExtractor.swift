import Foundation

public struct ArchiveExtractor: Sendable {
    public static let supportedExtensions: Set<String> = ["zip", "cbz"]

    private let extractionRoot: URL

    public init(extractionRoot: URL) {
        self.extractionRoot = extractionRoot
    }

    public func extract(_ archiveURL: URL) throws -> URL {
        guard Self.isSupportedArchive(archiveURL) else {
            throw ArchiveExtractionError.unsupportedArchive(archiveURL)
        }

        let archiveFingerprint = try ImageFingerprint().make(for: archiveURL)
        let destinationURL = extractionRoot.appendingPathComponent(archiveFingerprint, isDirectory: true)
        let markerURL = destinationURL.appendingPathComponent(".manga-lada-extracted")

        if FileManager.default.fileExists(atPath: markerURL.path) {
            return destinationURL
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw ArchiveExtractionError.extractionFailed(
                archiveURL,
                exitCode: process.terminationStatus,
                message: message
            )
        }

        FileManager.default.createFile(atPath: markerURL.path, contents: Data())
        return destinationURL
    }

    public static func isSupportedArchive(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }
}

public enum ArchiveExtractionError: LocalizedError, Equatable {
    case unsupportedArchive(URL)
    case extractionFailed(URL, exitCode: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedArchive(let url):
            return "지원하지 않는 압축 파일입니다: \(url.lastPathComponent)"
        case .extractionFailed(let url, let exitCode, let message):
            let details = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if details.isEmpty {
                return "ZIP 압축 해제에 실패했습니다: \(url.lastPathComponent) (exit \(exitCode))"
            }
            return "ZIP 압축 해제에 실패했습니다: \(url.lastPathComponent) (exit \(exitCode)) \(details)"
        }
    }
}
