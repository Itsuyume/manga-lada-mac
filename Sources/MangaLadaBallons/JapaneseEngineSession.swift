import Foundation
import MangaLadaCore

/// Serial model session; successful requests reuse detection, OCR and inpaint weights.
public actor JapaneseEngineSession {
    private let engine: BallonsTranslatorEngine
    private var connection: JapaneseEngineConnection?
    private var processing = false
    private var idleShutdown: Task<Void, Never>?
    private var idleGeneration: UUID?
    public init(engine: BallonsTranslatorEngine) { self.engine = engine }
    deinit { idleShutdown?.cancel() }

    public func recognizeAndClean(source: URL, runID: String, priorBlocks: [TextBlock]? = nil,
                                  opticalCandidates: [TextBlock] = [],
                                  ocrBackend: JapaneseOCRBackend = .manga,
                                  rereadExisting: Bool = false,
                                  sourceLanguage: LanguageCode = .japanese,
                                  idleTimeout: Duration = OllamaConfiguration.Retention.balanced.duration) async throws -> PageTranslation {
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        let blocks = try await exchange(Request(source: source.path, destination: engine.inpaintedImageURL(runID: runID).path,
                                               blocks: priorBlocks, regions: nil, soundEffectSources: lexicon.sourceForms,
                                               soundEffectPatterns: lexicon.recognitionPatterns, opticalCandidates: opticalCandidates,
                                               ocrBackend: ocrBackend, rereadExisting: rereadExisting,
                                               sourceLanguage: sourceLanguage), idleTimeout: idleTimeout)
        return PageTranslation(imageURL: source, imageFingerprint: runID, sourceLanguage: sourceLanguage, targetLanguage: .korean, blocks: blocks)
    }
    public func verifyProposedRegions(source: URL, regions: [TextBlock],
                                      ocrBackend: JapaneseOCRBackend = .manga,
                                      sourceLanguage: LanguageCode = .japanese, opticalCandidates: [TextBlock] = [],
                                      idleTimeout: Duration = OllamaConfiguration.Retention.balanced.duration) async throws -> [TextBlock] {
        guard !regions.isEmpty else { return [] }
        return try await exchange(Request(source: source.path, destination: nil, blocks: nil, regions: regions,
                                          soundEffectSources: nil, soundEffectPatterns: nil, opticalCandidates: opticalCandidates,
                                          ocrBackend: ocrBackend, rereadExisting: false,
                                          sourceLanguage: sourceLanguage), idleTimeout: idleTimeout)
    }
    private func exchange(_ value: Request, idleTimeout: Duration) async throws -> [TextBlock] {
        guard !processing else { throw JapaneseEngineSessionError.busy }
        try Task.checkCancellation()
        let request = try JSONEncoder().encode(value)
        cancelIdleShutdown()
        processing = true; defer { processing = false }
        let worker: JapaneseEngineConnection
        if let connection { worker = connection }
        else { worker = try JapaneseEngineConnection(engine: engine); connection = worker }
        do {
            let data = try await withTaskCancellationHandler {
                try await Task.detached { try worker.exchange(request) }.value
            } onCancel: { worker.terminate() }
            try Task.checkCancellation()
            let response = try JSONDecoder().decode(Response.self, from: data)
            if let error = response.error { throw JapaneseEngineSessionError.processing(error) }
            guard let blocks = response.blocks else { throw JapaneseEngineSessionError.invalidResponse }
            scheduleIdleShutdown(after: idleTimeout)
            return blocks
        } catch {
            worker.terminate(); connection = nil
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
    public func stop() {
        cancelIdleShutdown()
        connection?.terminate(); connection = nil
    }
    private func cancelIdleShutdown() {
        idleShutdown?.cancel(); idleShutdown = nil; idleGeneration = nil
    }
    private func scheduleIdleShutdown(after delay: Duration) {
        let generation = UUID(); idleGeneration = generation
        idleShutdown = Task { [weak self] in
            do { try await Task.sleep(for: delay) }
            catch { return } // Task.sleep only throws when its wait is cancelled.
            await self?.expireConnection(generation: generation)
        }
    }
    private func expireConnection(generation: UUID) {
        guard idleGeneration == generation, !processing else { return }
        stop()
    }
    private struct Request: Encodable {
        let source: String; let destination: String?; let blocks: [TextBlock]?; let regions: [TextBlock]?
        let soundEffectSources: [String]?
        let soundEffectPatterns: [String]?
        let opticalCandidates: [TextBlock]?
        let ocrBackend: JapaneseOCRBackend
        let rereadExisting: Bool
        let sourceLanguage: LanguageCode
    }
    private struct Response: Decodable { let blocks: [TextBlock]?; let error: String? }
}
