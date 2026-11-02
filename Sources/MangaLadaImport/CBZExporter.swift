import Foundation
import MangaLadaCore

public struct CBZExporter: Sendable {
    public init() {}
    public func export(pages: [URL], to destination: URL, progress: @escaping @Sendable (Int) -> Void = { _ in }) async throws {
        guard !pages.isEmpty else { throw ComicImportError.emptyBook }
        let cancellation = CancellableProcess()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try exportSynchronously(pages: pages, destination: destination, cancellation: cancellation, progress: progress)
            }.value
        } onCancel: { cancellation.cancel() }
    }
    private func exportSynchronously(pages: [URL], destination: URL, cancellation: CancellableProcess,
                                    progress: @Sendable (Int) -> Void) throws {
        try cancellation.checkCancellation()
        _ = try RegularFileTarget.exists(at: destination)
        let root = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: destination, create: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (index, page) in pages.enumerated() {
            try cancellation.checkCancellation()
            let name = String(format: "%05d", index + 1) + "." + page.pathExtension
            try FileManager.default.copyItem(at: page, to: root.appendingPathComponent(name))
            progress(index + 1)
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
            let bytes = try Data(contentsOf: logURL)
            throw CBZExportError.compressionFailed(process.terminationStatus, String(String(decoding: bytes, as: UTF8.self).suffix(1600)))
        }
        try cancellation.checkCancellation()
        if try RegularFileTarget.exists(at: destination) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: archive)
        } else { try FileManager.default.moveItem(at: archive, to: destination) }
    }
}

public enum CBZExportError: LocalizedError {
    case compressionFailed(Int32, String)
    public var errorDescription: String? {
        switch self {
        case .compressionFailed(let code, let message): "CBZ 파일로 묶지 못했습니다. (exit \(code)) \(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
