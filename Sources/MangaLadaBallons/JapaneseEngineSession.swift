import Foundation
import MangaLadaCore

/// Serial model session; successful requests reuse detection, OCR and inpaint weights.
public actor JapaneseEngineSession {
    private let engine: BallonsTranslatorEngine
    private var connection: JapaneseEngineConnection?
    private var processing = false
    public init(engine: BallonsTranslatorEngine) { self.engine = engine }

    public func recognizeAndClean(source: URL, runID: String, priorBlocks: [TextBlock]? = nil) async throws -> PageTranslation {
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        let blocks = try await exchange(Request(source: source.path, destination: engine.inpaintedImageURL(runID: runID).path,
                                               blocks: priorBlocks, regions: nil, soundEffectSources: lexicon.sourceForms,
                                               soundEffectPatterns: lexicon.recognitionPatterns))
        return PageTranslation(imageURL: source, imageFingerprint: runID, sourceLanguage: .japanese, targetLanguage: .korean, blocks: blocks)
    }
    public func verifyProposedRegions(source: URL, regions: [TextBlock]) async throws -> [TextBlock] {
        guard !regions.isEmpty else { return [] }
        return try await exchange(Request(source: source.path, destination: nil, blocks: nil, regions: regions,
                                          soundEffectSources: nil, soundEffectPatterns: nil))
    }
    private func exchange(_ value: Request) async throws -> [TextBlock] {
        guard !processing else { throw JapaneseEngineSessionError.busy }
        try Task.checkCancellation()
        processing = true; defer { processing = false }
        let worker: JapaneseEngineConnection
        if let connection { worker = connection }
        else { worker = try JapaneseEngineConnection(engine: engine); connection = worker }
        let request = try JSONEncoder().encode(value)
        do {
            let data = try await withTaskCancellationHandler {
                try await Task.detached { try worker.exchange(request) }.value
            } onCancel: { worker.terminate() }
            try Task.checkCancellation()
            let response = try JSONDecoder().decode(Response.self, from: data)
            if let error = response.error { throw JapaneseEngineSessionError.processing(error) }
            guard let blocks = response.blocks else { throw JapaneseEngineSessionError.invalidResponse }
            return blocks
        } catch {
            worker.terminate(); connection = nil
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
    public func stop() { connection?.terminate(); connection = nil }
    private struct Request: Encodable {
        let source: String; let destination: String?; let blocks: [TextBlock]?; let regions: [TextBlock]?
        let soundEffectSources: [String]?
        let soundEffectPatterns: [String]?
    }
    private struct Response: Decodable { let blocks: [TextBlock]?; let error: String? }
}
