import Foundation

/// Process is confined behind the lock; cancellation can arrive from a different task.
public final class CancellableProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}
    public func cancel() {
        let active = lock.withLock { cancelled = true; return process }
        if let active, active.isRunning { active.terminate() }
    }

    public func checkCancellation() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }

    public func run(_ candidate: Process) throws {
        let alreadyCancelled = lock.withLock { process = candidate; return cancelled }
        defer { lock.withLock { process = nil } }
        guard !alreadyCancelled else { throw CancellationError() }
        try candidate.run()
        let mustTerminate = lock.withLock { cancelled }
        if mustTerminate, candidate.isRunning { candidate.terminate() }
        candidate.waitUntilExit()
        try checkCancellation()
    }
}
