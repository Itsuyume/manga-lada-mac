import Foundation
import MangaLadaCore

@MainActor
final class LocalModelRuntime {
    private var server: Process?
    func ensureReady(model: String) async throws {
        try validate(model)
        let models: [String]
        do { models = try await installedModels() }
        catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .timedOut].contains(error.code) {
            try startServer(); models = try await waitForServer()
        }
        guard models.contains(model) || models.contains(model + ":latest") else { throw LocalRuntimeError.modelMissing(model) }
    }
    func prepare(model: String) async throws {
        try validate(model)
        do { _ = try await installedModels() }
        catch let error as URLError where error.code == .cannotConnectToHost { try startServer(); _ = try await waitForServer() }
        let command = try executable()
        let logURL = AppPaths.support.appendingPathComponent("ollama-model-setup.log")
        try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        try Data().write(to: logURL)
        let cancellation = CancellableProcess()
        try await withTaskCancellationHandler {
            try await Task.detached {
                let handle = try FileHandle(forWritingTo: logURL); defer { try? handle.close() }
                let process = Process(); process.executableURL = command; process.arguments = ["pull", model]
                process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
                try cancellation.run(process)
                guard process.terminationStatus == 0 else {
                    throw LocalRuntimeError.setupFailed(String((try String(contentsOf: logURL, encoding: .utf8)).suffix(800)))
                }
            }.value
        } onCancel: { cancellation.cancel() }
        try await ensureReady(model: model)
    }
    private func validate(_ model: String) throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.lowercased().contains("cloud"), model.count <= 100 else { throw LocalRuntimeError.invalidModel }
    }
    private func installedModels() async throws -> [String] {
        let url = URL(string: "http://127.0.0.1:11434/api/tags")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 2))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LocalRuntimeError.serverFailed }
        return try JSONDecoder().decode(ModelList.self, from: data).models.map(\.name)
    }
    private func waitForServer() async throws -> [String] {
        for _ in 0..<20 {
            try Task.checkCancellation()
            do { return try await installedModels() }
            catch let error as URLError where error.code == .cannotConnectToHost { try await Task.sleep(for: .milliseconds(250)) }
        }
        throw LocalRuntimeError.serverFailed
    }
    private func startServer() throws {
        let logURL = AppPaths.support.appendingPathComponent("ollama-server.log")
        try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logURL.path) { try Data().write(to: logURL) }
        let log = try FileHandle(forWritingTo: logURL); try log.seekToEnd(); defer { try? log.close() }
        let process = Process(); process.executableURL = try executable(); process.arguments = ["serve"]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = log; process.standardError = log
        process.environment = ProcessInfo.processInfo.environment.merging(["OLLAMA_HOST": "127.0.0.1:11434", "OLLAMA_NO_CLOUD": "1"]) { _, value in value }
        try process.run(); server = process
    }
    private func executable() throws -> URL {
        let directories = ["/opt/homebrew/bin", "/usr/local/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        guard let path = directories.map({ $0 + "/ollama" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw LocalRuntimeError.notInstalled }
        return URL(fileURLWithPath: path)
    }
    private struct ModelList: Decodable { let models: [Model]; struct Model: Decodable { let name: String } }
}

private enum LocalRuntimeError: LocalizedError {
    case notInstalled, invalidModel, serverFailed, modelMissing(String), setupFailed(String)
    var errorDescription: String? {
        switch self {
        case .notInstalled: "Ollama가 설치되어 있지 않습니다. ollama.com에서 Mac용 Ollama를 설치해주세요."
        case .invalidModel: "로컬 모델 이름을 확인해주세요. 클라우드 모델은 로컬 모드에서 사용할 수 없습니다."
        case .serverFailed: "로컬 Ollama에 연결하지 못했습니다. Ollama 실행 상태를 확인해주세요."
        case .modelMissing(let name): "\(name) 모델이 없습니다. 설정에서 ‘로컬 모델 준비’를 눌러 내려받아주세요."
        case .setupFailed(let detail): "로컬 모델 준비에 실패했습니다. \(detail)"
        }
    }
}
