import Foundation
import MangaLadaCore

public struct CBZExporter: Sendable {
    public init() {}
    public func export(pages: [URL], to destination: URL) async throws {
        guard !pages.isEmpty else { throw ComicImportError.emptyBook }
        let cancellation = CancellableProcess()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try exportSynchronously(pages: pages, destination: destination, cancellation: cancellation)
            }.value
        } onCancel: { cancellation.cancel() }
    }
    private func exportSynchronously(pages: [URL], destination: URL, cancellation: CancellableProcess) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("comic-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            let name = String(format: "%05d", index + 1) + "." + page.pathExtension
            try FileManager.default.copyItem(at: page, to: root.appendingPathComponent(name))
        }
        let archive = root.appendingPathComponent("book.cbz")
        let logURL = root.appendingPathComponent("export.log"); try Data().write(to: logURL)
        let log = try FileHandle(forWritingTo: logURL); defer { try? log.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip"); process.currentDirectoryURL = root
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != "export.log" }.sorted()
        process.arguments = ["-q", archive.path] + names
        process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
        try cancellation.run(process)
        guard process.terminationStatus == 0 else {
            throw ArchiveExtractionError.extractionFailed(destination, exitCode: process.terminationStatus, message: try String(contentsOf: logURL, encoding: .utf8))
        }
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
    }
}
