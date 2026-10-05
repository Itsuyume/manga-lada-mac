import Foundation
import ImageIO
import MangaLadaCore
import MangaLadaVision
import UniformTypeIdentifiers

enum SupplementalJapaneseOCR {
    static func recognize(in imageURL: URL, existing blocks: [TextBlock],
                          retention: OllamaConfiguration.Retention,
                          verifyProposals: @Sendable ([TextBlock]) async throws -> [TextBlock]) async throws -> (blocks: [TextBlock], extras: [TextBlock], unverified: Int) {
        var candidates = try await VisionOCRService().recognizeText(in: imageURL, recognitionLanguages: ["ja-JP"])
        let imageData = try await Task.detached { try prepareVisionImage(imageURL) }.value
        let configuration = OllamaConfiguration(model: OllamaConfiguration.visionModel, retention: retention)
        let effects = try await OllamaSoundEffectDetector(configuration: configuration).recognize(imageData: imageData)
        let cropped = try await verifyProposals(effects)
        candidates += cropped.filter { recognized in recognized.recognitionAlternatives == nil && effects.contains { effect in
            effect.id == recognized.id && effect.originalText.filter { !$0.isWhitespace } == recognized.originalText.filter { !$0.isWhitespace }
        } }
        return JapaneseRegionMerger.merge(existing: blocks, effects: effects, opticalCandidates: candidates)
    }

    private static func prepareVisionImage(_ url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return data as Data
    }

}
