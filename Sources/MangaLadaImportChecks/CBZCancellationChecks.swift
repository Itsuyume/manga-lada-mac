import Foundation
import MangaLadaCore
import MangaLadaImport

enum CBZCancellationChecks {
    static func run(root: URL, source: URL) async throws {
        let destination = root.appendingPathComponent("cancelled-export.cbz")
        let existingArchive = Data("previous successful archive".utf8)
        let sourceBytes = try Data(contentsOf: source)
        try existingArchive.write(to: destination)
        let before = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await CBZExporter().export(pages: [source], to: destination)
        }
        do { try await before.value; throw Failure.failed("Already-cancelled CBZ export succeeded.") }
        catch is CancellationError { }
        let pages = Array(repeating: source, count: 3_000) + [root.appendingPathComponent("must-not-be-read.png")]
        let (copied, observer) = AsyncStream.makeStream(of: Int.self)
        let export = Task {
            defer { observer.finish() }
            try await CBZExporter().export(pages: pages, to: destination) { observer.yield($0) }
        }
        for await count in copied where count >= 10 { export.cancel(); break }
        do { try await export.value; throw Failure.failed("Cancelled CBZ export succeeded.") }
        catch is CancellationError { }
        guard try Data(contentsOf: destination) == existingArchive, try Data(contentsOf: source) == sourceBytes else {
            throw Failure.failed("CBZ cancellation changed the previous archive or source image.")
        }
        try await checkRunningProcessCancellation()
        try await CBZExporter().export(pages: [source], to: destination)
        let restored = try await ComicBookLoader(extractionRoot: root.appendingPathComponent("replaced-cbz-cache")).load(destination)
        guard restored.pages.count == 1, try Data(contentsOf: restored.pages[0].url) == sourceBytes else {
            throw Failure.failed("Replacing a CBZ did not preserve page bytes.")
        }
        let directory = root.appendingPathComponent("directory-target.cbz")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let sentinel = directory.appendingPathComponent("keep.txt")
        try existingArchive.write(to: sentinel)
        do { try await CBZExporter().export(pages: [source], to: directory); throw Failure.failed("A directory was replaced by an archive.") }
        catch is RegularFileTarget.Failure { }
        guard try Data(contentsOf: sentinel) == existingArchive else { throw Failure.failed("Invalid export removed directory contents.") }
        for (name, target) in [("link.cbz", destination), ("dangling.cbz", root.appendingPathComponent("missing-target.cbz"))] {
            let link = root.appendingPathComponent(name)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let before = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            do { try await CBZExporter().export(pages: [source], to: link); throw Failure.failed("A symbolic link was replaced by an archive.") }
            catch is RegularFileTarget.Failure { }
            guard try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == before else {
                throw Failure.failed("Invalid export modified a symbolic link.")
            }
        }
        print("CBZ cancellation checks passed: before/during copy, no later source access, previous archive and source preserved")
    }

    private static func checkRunningProcessCancellation() async throws {
        let cancellation = CancellableProcess()
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["30"]
        let running = Task.detached { try cancellation.run(process) }
        let deadline = Date().addingTimeInterval(5)
        while !process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard process.isRunning else { cancellation.cancel(); throw Failure.failed("Child process did not start.") }
        cancellation.cancel()
        do { try await running.value; throw Failure.failed("Cancelling a running process succeeded.") }
        catch is CancellationError { }
        guard !process.isRunning else { throw Failure.failed("Cancelled child process was left running.") }
        do { try cancellation.checkCancellation(); throw Failure.failed("Cancellation state was cleared after process exit.") }
        catch is CancellationError { }
    }
    private enum Failure: Error { case failed(String) }
}
