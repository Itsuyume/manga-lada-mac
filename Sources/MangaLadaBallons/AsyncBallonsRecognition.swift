import Foundation
import MangaLadaCore

extension BallonsTranslatorEngine {
    public func recognizeAndClean(sourceImageURL: URL, runID: String) async throws -> BallonsTranslationResult {
        let cancellation = CancellableProcess()
        return try await withTaskCancellationHandler {
            let task = Task.detached(priority: .userInitiated) {
                try translate(sourceImageURL: sourceImageURL, runID: runID, imageFingerprint: runID,
                              sourceLanguage: .japanese, targetLanguage: .korean,
                              enableTranslation: false, cancellation: cancellation)
            }
            return try await task.value
        } onCancel: { cancellation.cancel() }
    }
}
