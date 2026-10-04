import Darwin
import Foundation
import MangaLadaBallons
import MangaLadaCore

/// A real subprocess stands in for the external model boundary; session logic is unchanged.
enum SessionLifetimeChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("JapaneseSession-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("ballontranslator"), withIntermediateDirectories: true)
        let script = root.appendingPathComponent("worker.py")
        try Data(worker.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let engine = BallonsTranslatorEngine(pythonURL: script, sourceRootURL: root, runsDirectoryURL: root.appendingPathComponent("runs"))
        let session = JapaneseEngineSession(engine: engine)
        do {
            try await checkReuseAndExpiry(session, root: root)
            try await checkActiveAndFailedRequests(session, root: root)
            await session.stop()
            try FileManager.default.removeItem(at: root)
        } catch {
            await session.stop()
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        print("OCR session lifetime passed: empty input, PID reuse, deadline renewal, automatic exit/restart, active work, cancellation, invalid response and explicit stop")
    }

    private static func checkReuseAndExpiry(_ session: JapaneseEngineSession, root: URL) async throws {
        let source = root.appendingPathComponent("page.png")
        let empty = try await session.verifyProposedRegions(source: source, regions: [], idleTimeout: .milliseconds(800))
        try require(empty.isEmpty && !FileManager.default.fileExists(atPath: root.appendingPathComponent("state.json").path),
                    "An empty request launched the OCR process.")
        var invalid = block("無効"); invalid.box.x = .nan
        do {
            _ = try await session.verifyProposedRegions(source: source, regions: [invalid])
            throw CheckError.failed("A nonfinite request was accepted.")
        } catch is EncodingError { }
        try require(!FileManager.default.fileExists(atPath: root.appendingPathComponent("state.json").path),
                    "A request that could not be encoded launched the OCR process.")
        let region = block("静かだ。")
        let first = try await session.verifyProposedRegions(source: source, regions: [region], idleTimeout: .milliseconds(800))
        try require(first == [region], "The process response changed region data.")
        let initial = try state(root)
        try await Task.sleep(for: .milliseconds(500))
        _ = try await session.verifyProposedRegions(source: source, regions: [region], idleTimeout: .milliseconds(800))
        let reused = try state(root)
        try require(reused.pid == initial.pid && reused.count == 2, "Consecutive requests reloaded the OCR process.")
        try await Task.sleep(for: .milliseconds(400))
        try require(alive(initial.pid), "An old idle deadline terminated a recently used process.")
        try await waitUntil("The idle OCR process did not exit.") { !alive(initial.pid) }
        _ = try await session.verifyProposedRegions(source: source, regions: [region], idleTimeout: .milliseconds(800))
        let restarted = try state(root)
        try require(restarted.pid != initial.pid && restarted.count == 1, "An expired OCR process was not restarted.")
    }

    private static func checkActiveAndFailedRequests(_ session: JapaneseEngineSession, root: URL) async throws {
        let source = root.appendingPathComponent("page.png")
        let slow = block("wait")
        let pending = Task { try await session.verifyProposedRegions(source: source, regions: [slow], idleTimeout: .milliseconds(200)) }
        try await waitUntil("The slow request did not reach the process.") { try state(root).text == "wait" }
        do {
            _ = try await session.verifyProposedRegions(source: source, regions: [block("busy")])
            throw CheckError.failed("A concurrent request entered the serial OCR session.")
        } catch let error as CheckError { throw error }
        catch { }
        try require(try state(root).text == "wait", "The rejected concurrent request reached the model process.")
        let response = try await pending.value
        try require(response == [slow], "The idle timer interrupted active OCR.")
        let activePID = try state(root).pid
        let cancelled = Task { try await session.verifyProposedRegions(source: source, regions: [block("cancel")], idleTimeout: .milliseconds(200)) }
        try await waitUntil("Cancellation request did not reach the process.") { try state(root).text == "cancel" }
        cancelled.cancel()
        do { _ = try await cancelled.value; throw CheckError.failed("Cancelled OCR returned success.") }
        catch is CancellationError { }
        try await waitUntil("Cancelled OCR process remained alive.") { !alive(activePID) }
        do {
            _ = try await session.verifyProposedRegions(source: source, regions: [block("invalid")], idleTimeout: .milliseconds(200))
            throw CheckError.failed("An invalid model response was accepted.")
        } catch let error as CheckError { throw error }
        catch is DecodingError { }
        let invalidPID = try state(root).pid
        try await waitUntil("Invalid-response process remained alive.") { !alive(invalidPID) }
        _ = try await session.verifyProposedRegions(source: source, regions: [block("再開")], idleTimeout: .seconds(2))
        let finalPID = try state(root).pid
        try require(finalPID != invalidPID, "Failed OCR session did not recover on a new request.")
        await session.stop()
        try await waitUntil("Explicit stop did not terminate the process.") { !alive(finalPID) }
    }

    private static func block(_ text: String) -> TextBlock {
        TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), originalText: text)
    }
    private static func state(_ root: URL) throws -> WorkerState {
        try JSONDecoder().decode(WorkerState.self, from: Data(contentsOf: root.appendingPathComponent("state.json")))
    }
    private static func alive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }
    private static func waitUntil(_ message: String, condition: () throws -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while try !condition() {
            guard ContinuousClock.now < deadline else { throw CheckError.failed(message) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckError.failed(message) }
    }
    private struct WorkerState: Decodable { let pid: Int32; let count: Int; let text: String }
    private enum CheckError: LocalizedError {
        case failed(String)
        var errorDescription: String? { switch self { case .failed(let message): message } }
    }
    private static let worker = #"""
    #!/usr/bin/env python3
    import json, os, sys, time
    from pathlib import Path
    root = Path(sys.argv[-1])
    count = 0
    for line in sys.stdin:
        request = json.loads(line)
        regions = request["regions"]
        text = regions[0]["originalText"]
        count += 1
        temporary = root / "state.partial.json"
        temporary.write_text(json.dumps({"pid": os.getpid(), "count": count, "text": text}))
        os.replace(temporary, root / "state.json")
        if text in ("wait", "cancel"):
            time.sleep(1.2)
        print("{" if text == "invalid" else json.dumps({"blocks": regions}), flush=True)
    """#
}
