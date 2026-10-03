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

    public func run(_ candidate: Process) throws {
        let alreadyCancelled = lock.withLock { process = candidate; return cancelled }
        guard !alreadyCancelled else { throw CancellationError() }
        try candidate.run()
        let mustTerminate = lock.withLock { cancelled }
        if mustTerminate, candidate.isRunning { candidate.terminate() }
        candidate.waitUntilExit()
        let wasCancelled = lock.withLock { process = nil; return cancelled }
        if wasCancelled { throw CancellationError() }
    }
}
