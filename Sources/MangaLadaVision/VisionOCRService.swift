import Foundation
import ImageIO
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

            let handler: VNImageRequestHandler
            if recognitionLanguages == ["en-US"], let image = try Self.enlargedEnglishImage(imageURL) {
                handler = VNImageRequestHandler(cgImage: image)
            } else {
                handler = VNImageRequestHandler(url: imageURL)
            }
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

    /// Preserve normalized coordinates while giving small English lettering enough pixels.
    private static func enlargedEnglishImage(_ url: URL) throws -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1_200
              ] as CFDictionary) else { throw OCRServiceError.imageDecodeFailed }
        let longest = max(image.width, image.height)
        guard longest < 1_000 else { return nil }
        let scale = min(3, 1_200.0 / Double(longest))
        guard let context = CGContext(data: nil, width: Int(Double(image.width) * scale), height: Int(Double(image.height) * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw OCRServiceError.imageDecodeFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let enlarged = context.makeImage() else { throw OCRServiceError.imageDecodeFailed }
        return enlarged
    }
}

public enum OCRServiceError: LocalizedError {
    case imageDecodeFailed
    public var errorDescription: String? { "글자 인식을 위해 이미지를 읽지 못했습니다." }
}
