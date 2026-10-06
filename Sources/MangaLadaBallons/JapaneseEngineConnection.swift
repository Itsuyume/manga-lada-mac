import Darwin
import Foundation

/// File handles belong to one worker request. Only cancellation crosses threads.
final class JapaneseEngineConnection: @unchecked Sendable {
    /// Region outlines on dense pages can exceed a megabyte; the bound only stops a runaway worker.
    private static let responseLimit = 32_000_000
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let lock = NSLock()
    private var pending = Data()

    init(engine: BallonsTranslatorEngine) throws {
        guard engine.isInstalled else { throw BallonsTranslatorEngineError.engineNotInstalled }
        guard let script = Bundle.module.url(forResource: "japanese_engine_worker", withExtension: "py") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: engine.runsDirectoryURL, withIntermediateDirectories: true)
        let logURL = engine.runsDirectoryURL.appendingPathComponent("japanese-worker.log")
        if !FileManager.default.fileExists(atPath: logURL.path) { try Data().write(to: logURL) }
        let log = try FileHandle(forWritingTo: logURL); try log.seekToEnd(); defer { try? log.close() }
        let incoming = Pipe(), outgoing = Pipe()
        process = Process(); process.executableURL = engine.pythonURL
        process.arguments = ["-u", script.path, engine.sourceRootURL.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1", "QT_QPA_PLATFORM": "offscreen", "HF_HUB_OFFLINE": "1"
        ]) { _, value in value }
        process.standardInput = incoming; process.standardOutput = outgoing; process.standardError = log
        input = incoming.fileHandleForWriting; output = outgoing.fileHandleForReading
        // A worker that exits while idle must surface as EPIPE, not a SIGPIPE that ends the app.
        guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EBADF)
        }
        try process.run()
        try incoming.fileHandleForReading.close(); try outgoing.fileHandleForWriting.close()
    }
    var isRunning: Bool { lock.withLock { process.isRunning } }
    func exchange(_ request: Data) throws -> Data {
        guard isRunning else { throw JapaneseEngineSessionError.workerStopped }
        do { try input.write(contentsOf: request + Data([10])) }
        catch { throw JapaneseEngineSessionError.workerStopped }
        while true {
            if let newline = pending.firstIndex(of: 10) {
                let response = Data(pending[pending.startIndex..<newline])
                pending.removeSubrange(pending.startIndex...newline)
                return response
            }
            guard pending.count <= Self.responseLimit else { throw JapaneseEngineSessionError.invalidResponse }
            try readAvailable()
        }
    }
    /// One read(2) returns whatever the worker has written. `FileHandle.read(upToCount:)` would
    /// wait for the full chunk and stall on a short reply from a worker that stays alive.
    private func readAvailable() throws {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(output.fileDescriptor, $0.baseAddress, $0.count) }
            if count > 0 { pending.append(contentsOf: buffer[0..<count]); return }
            if count == 0 { throw JapaneseEngineSessionError.workerStopped }
            guard errno == EINTR else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
    }
    func terminate() { lock.withLock { if process.isRunning { process.terminate() } } }
    deinit { terminate(); try? input.close(); try? output.close() }
}

enum JapaneseEngineSessionError: LocalizedError {
    case workerStopped, invalidResponse, busy, processing(String)
    var errorDescription: String? {
        switch self {
        case .workerStopped: "일본어 인식 엔진이 종료되었습니다. Japanese worker 로그를 확인해주세요."
        case .invalidResponse: "일본어 인식 엔진 응답이 올바르지 않습니다."
        case .busy: "일본어 인식 엔진이 이미 다른 페이지를 처리하고 있습니다."
        case .processing(let message): "일본어 인식 실패: \(message)"
        }
    }
}
