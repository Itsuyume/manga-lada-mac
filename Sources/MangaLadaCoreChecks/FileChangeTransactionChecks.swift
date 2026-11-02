import Foundation
import MangaLadaCore

enum FileChangeTransactionChecks {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("file-rollback-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existing = root.appendingPathComponent("existing"), created = root.appendingPathComponent("new")
        let before = Data("original bytes".utf8)
        try before.write(to: existing)
        do {
            try FileChangeTransaction.withRollback(at: [existing, created, existing]) {
                try Data("modified".utf8).write(to: existing, options: .atomic)
                try Data("new".utf8).write(to: created, options: .atomic)
                throw Failure.expected
            }
            throw Failure.notRejected
        } catch Failure.expected { }
        try check(Data(contentsOf: existing) == before && !FileManager.default.fileExists(atPath: created.path), "Rollback lost old bytes or retained a new file.")
        try FileChangeTransaction.withRollback(at: [existing]) { try Data("committed".utf8).write(to: existing, options: .atomic) }
        try check(Data(contentsOf: existing) == Data("committed".utf8), "A successful write was rolled back.")
        let directory = root.appendingPathComponent("directory")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        var called = false
        do { try FileChangeTransaction.withRollback(at: [directory]) { called = true }; throw Failure.notRejected }
        catch Failure.notRejected { throw Failure.notRejected }
        catch { }
        try check(!called && FileManager.default.fileExists(atPath: directory.path), "An invalid destination reached the mutating action.")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existing)
        do { try FileChangeTransaction.withRollback(at: [link]) { called = true }; throw Failure.notRejected }
        catch Failure.notRejected { throw Failure.notRejected }
        catch { }
        try check(!called && Data(contentsOf: existing) == Data("committed".utf8), "A symbolic-link target was modified.")
        print("File rollback checks passed: existing/new/duplicate paths, successful writes, invalid targets and symlink preservation")
    }
    private static func check(_ value: Bool, _ message: String) throws { try NetworkBoundaryChecks.check(value, message) }
    private enum Failure: Error { case expected, notRejected }
}
