import Foundation
import MangaLadaCore

extension BallonsTranslatorEngine {
    public func eraseSupplementalText(_ blocks: [TextBlock], cleanImageURL: URL, bounded: Bool = false, maskSourceURL: URL? = nil) async throws {
        guard !blocks.isEmpty else { return }
        let cancellation = CancellableProcess()
        try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try eraseSynchronously(blocks, cleanImageURL: cleanImageURL, bounded: bounded, maskSourceURL: maskSourceURL, cancellation: cancellation)
            }.value
        } onCancel: { cancellation.cancel() }
    }

    private func eraseSynchronously(_ blocks: [TextBlock], cleanImageURL: URL, bounded: Bool, maskSourceURL: URL?,
                                    cancellation: CancellableProcess) throws {
        guard let script = Bundle.module.url(forResource: "erase_supplemental_text", withExtension: "py") else {
            throw BallonsTranslatorEngineError.engineNotInstalled
        }
        let regionsURL = cleanImageURL.deletingLastPathComponent().appendingPathComponent("supplemental-regions.json")
        let boxes = blocks.map { bounded ? $0.userDefinedBounds ?? $0.box : $0.box }
        try JSONEncoder().encode(InpaintRegions(regions: boxes, bounded: bounded, maskSource: maskSourceURL?.path)).write(to: regionsURL, options: .atomic)
        let logURL = cleanImageURL.deletingLastPathComponent().appendingPathComponent("supplemental.log")
        try Data().write(to: logURL)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let process = Process()
        process.executableURL = pythonURL
        process.arguments = [script.path, sourceRootURL.path, cleanImageURL.path, regionsURL.path]
        process.currentDirectoryURL = sourceRootURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "QT_QPA_PLATFORM": "offscreen", "PYTHONUNBUFFERED": "1"
        ]) { _, value in value }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        try cancellation.run(process)
        guard process.terminationStatus == 0 else {
            let detail = try String(contentsOf: logURL, encoding: .utf8)
            throw BallonsTranslatorEngineError.processFailed(process.terminationStatus, String(detail.suffix(1_600)))
        }
    }
}

private struct InpaintRegions: Encodable { let regions: [TextBox]; let bounded: Bool; let maskSource: String? }
