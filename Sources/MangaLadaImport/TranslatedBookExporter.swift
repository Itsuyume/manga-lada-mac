import Foundation
import MangaLadaCore

/// Saves a finished book where the user chose in the Finder save panel. A multi-page book becomes
/// a folder that mirrors the source layout (subfolders kept, every page saved as PNG); the caller
/// saves a one-page book as a single PNG. Pages are staged beside the destination and moved in only
/// after every page was copied, so failure or cancellation never leaves a half-written folder and an
/// existing folder is replaced only when it is empty or an earlier export of this app.
public struct TranslatedBookExporter: Sendable {
    public static let marker = ".manga-translator-export"

    public struct Page: Equatable, Sendable {
        public let rendered: URL
        public let relativePath: String
        public init(rendered: URL, relativePath: String) { self.rendered = rendered; self.relativePath = relativePath }
    }

    public init() {}

    /// Output names follow the source pages: their paths below the pages' common folder with a
    /// `.png` extension. Names that would collide on a case-insensitive volume, or a file that
    /// would shadow a folder, fall back to numbered names so no page overwrites another.
    public static func layout(rendered: [URL], sources: [URL]) throws -> [Page] {
        guard !rendered.isEmpty, rendered.count == sources.count else { throw TranslatedBookExportError.pageMismatch }
        let paths = sources.map { $0.standardizedFileURL.pathComponents }
        let base = paths.dropFirst().reduce(Array(paths[0].dropLast())) { common, components in
            zip(common, components.dropLast()).prefix(while: { pair in pair.0 == pair.1 }).map(\.0)
        }
        var relative = paths.enumerated().map { index, components -> [String] in
            var parts = Array(components.dropFirst(base.count))
            let stem = (parts.last.map { ($0 as NSString).deletingPathExtension } ?? "").trimmingCharacters(in: .whitespaces)
            parts[parts.count - 1] = (stem.isEmpty || stem.hasPrefix(".") ? String(format: "%05d", index + 1) : stem) + ".png"
            return parts
        }
        let keys = relative.map { $0.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased() }
        let counts = Dictionary(keys.map { ($0, 1) }, uniquingKeysWith: +)
        for index in relative.indices where counts[keys[index], default: 0] > 1 {
            relative[index][relative[index].count - 1] = String(format: "%05d_", index + 1) + relative[index][relative[index].count - 1]
        }
        if !isValidLayout(relative) {
            relative = rendered.indices.map { [String(format: "%05d.png", $0 + 1)] }
        }
        return zip(rendered, relative).map { Page(rendered: $0, relativePath: $1.joined(separator: "/")) }
    }

    private static func isValidLayout(_ paths: [[String]]) -> Bool {
        let files = paths.map { $0.joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased() }
        let folders = Set(paths.flatMap { parts in
            parts.indices.dropLast().map { parts[...$0].joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased() }
        })
        return Set(files).count == files.count && folders.isDisjoint(with: files)
            && paths.allSatisfy { $0.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") } }
    }

    public func export(_ pages: [Page], to destination: URL) async throws {
        guard !pages.isEmpty else { throw TranslatedBookExportError.pageMismatch }
        let cancellation = ExportCancellation()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Self.exportSynchronously(pages, to: destination, cancellation: cancellation)
            }.value
        } onCancel: { cancellation.cancel() }
    }

    private static func exportSynchronously(_ pages: [Page], to destination: URL, cancellation: ExportCancellation) throws {
        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TranslatedBookExportError.missingParent(parent.lastPathComponent)
        }
        try checkReplaceable(destination)
        for page in pages where !fileManager.isReadableFile(atPath: page.rendered.path) {
            throw TranslatedBookExportError.missingPage(page.relativePath)
        }
        let staging = parent.appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for page in pages {
                guard !cancellation.isCancelled else { throw CancellationError() }
                let target = staging.appendingPathComponent(page.relativePath)
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: page.rendered, to: target)
            }
            try Data("Manga translator export\n".utf8).write(to: staging.appendingPathComponent(marker), options: .atomic)
            guard !cancellation.isCancelled else { throw CancellationError() }
            // Re-check right before the swap: the folder may have changed while pages were copied.
            try checkReplaceable(destination)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: staging) // Only the private staging folder is cleaned up.
            throw error
        }
    }

    /// An existing destination is replaced only when it is an empty folder or an earlier export.
    private static func checkReplaceable(_ destination: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) else { return }
        guard isDirectory.boolValue else { throw TranslatedBookExportError.occupied(destination.lastPathComponent) }
        let contents = try fileManager.contentsOfDirectory(atPath: destination.path).filter { $0 != ".DS_Store" }
        guard contents.isEmpty || contents.contains(marker) else { throw TranslatedBookExportError.occupied(destination.lastPathComponent) }
    }
}

private final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

public enum TranslatedBookExportError: LocalizedError, Equatable {
    case pageMismatch, missingParent(String), missingPage(String), occupied(String)
    public var errorDescription: String? {
        switch self {
        case .pageMismatch: "저장할 번역 페이지가 없거나 원본 페이지 수와 맞지 않습니다."
        case .missingParent(let name): "저장 위치 ‘\(name)’ 폴더를 찾을 수 없습니다."
        case .missingPage(let name): "번역된 페이지 ‘\(name)’ 파일을 찾을 수 없습니다. 해당 페이지를 다시 번역해주세요."
        case .occupied(let name): "‘\(name)’은(는) 이미 다른 파일이 들어 있는 위치입니다. 기존 파일을 보호하기 위해 저장하지 않았습니다. 다른 이름을 지정해주세요."
        }
    }
}
