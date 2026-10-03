import Foundation
import MangaLadaCore
import Vision

public struct VisionOCRService: Sendable {
    public init() {}

    public func recognizeText(in imageURL: URL, sourceLanguage: LanguageCode) async throws -> [TextBlock] {
        try await recognizeText(in: imageURL, recognitionLanguages: sourceLanguage.visionRecognitionLanguages)
    }

    public func recognizeText(in imageURL: URL, recognitionLanguages: [String], effectLexicon: JapaneseSoundEffectLexicon? = nil) async throws -> [TextBlock] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = recognitionLanguages
            request.minimumTextHeight = 0.01

            let handler = VNImageRequestHandler(url: imageURL)
            try handler.perform([request])

            let observations = request.results ?? []
            return observations.compactMap { observation in
                let candidates = observation.topCandidates(3)
                // Preserve sentence correction, but prefer a known effect spelling among
                // actual optical alternatives. Manga OCR independently verifies new regions.
                guard let candidate = candidates.first(where: { effectLexicon?.recognizes($0.string) == true }) ?? candidates.first else {
                    return nil
                }

                let normalizedBox = observation.boundingBox
                let box = TextBox(
                    x: normalizedBox.minX,
                    y: 1 - normalizedBox.maxY,
                    width: normalizedBox.width,
                    height: normalizedBox.height
                )

                return TextBlock(
                    box: box,
                    originalText: candidate.string,
                    confidence: candidate.confidence
                )
            }
        }.value
    }
}
