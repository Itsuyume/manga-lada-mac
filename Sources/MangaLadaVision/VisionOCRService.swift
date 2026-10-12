import Foundation
import ImageIO
import MangaLadaCore
import Vision

public struct VisionOCRService: Sendable {
    public init() {}

    public func recognizeText(in imageURL: URL, sourceLanguage: LanguageCode, regions: [TextBox] = []) async throws -> [TextBlock] {
        try await recognizeText(in: imageURL, recognitionLanguages: sourceLanguage.visionRecognitionLanguages, regions: regions)
    }

    public func recognizeText(in imageURL: URL, recognitionLanguages: [String], effectLexicon: JapaneseSoundEffectLexicon? = nil,
                              regions: [TextBox] = []) async throws -> [TextBlock] {
        guard regions.count <= 80, regions.allSatisfy(ImageRegionSelection.validates) else { throw OCRServiceError.invalidRegions }
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let handler: VNImageRequestHandler
            if recognitionLanguages == ["en-US"], let image = try Self.enlargedEnglishImage(imageURL) {
                handler = VNImageRequestHandler(cgImage: image)
            } else {
                handler = VNImageRequestHandler(url: imageURL)
            }
            let page = TextBox(x: 0, y: 0, width: 1, height: 1)
            let global = try Self.read(handler, languages: recognitionLanguages, effectLexicon: effectLexicon, region: page, regional: false)
            guard !regions.isEmpty else { return global }
            let sourceImage = try Self.uprightImage(imageURL)
            var local: [(TextBox, [TextBlock])] = []
            for region in regions {
                try Task.checkCancellation()
                local.append(try Self.readCrop(sourceImage, region: region, languages: recognitionLanguages, effectLexicon: effectLexicon))
            }
            try Task.checkCancellation()
            return VisionRegionRecognition.combine(global: global, regional: local)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static func readCrop(_ image: CGImage, region: TextBox, languages: [String], effectLexicon: JapaneseSoundEffectLexicon?) throws -> (TextBox, [TextBlock]) {
        let width = Double(image.width), height = Double(image.height)
        let left = floor(region.x * width), top = floor(region.y * height)
        let right = min(width, ceil((region.x + region.width) * width)), bottom = min(height, ceil((region.y + region.height) * height))
        guard let crop = image.cropping(to: CGRect(x: left, y: top, width: right-left, height: bottom-top)) else { throw OCRServiceError.imageDecodeFailed }
        let handler = VNImageRequestHandler(cgImage: try enlargedEnglishImage(crop) ?? crop)
        let lines = try read(handler, languages: languages, effectLexicon: effectLexicon, region: TextBox(x: 0, y: 0, width: 1, height: 1), regional: true)
        let actual = TextBox(x: left/width, y: top/height, width: (right-left)/width, height: (bottom-top)/height)
        let projected = lines.compactMap { line -> TextBlock? in
            guard let box = VisionRegionRecognition.project(line.box, into: actual) else { return nil }
            var block = line; block.box = box
            if box.height < 0.02 || box.y >= 0.1 { block.recognitionAlternatives = nil }
            return block
        }
        return (actual, projected)
    }

    private static func uprightImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height)
              ] as CFDictionary) else { throw OCRServiceError.imageDecodeFailed }
        return image
    }

    private static func read(_ handler: VNImageRequestHandler, languages: [String], effectLexicon: JapaneseSoundEffectLexicon?,
                             region: TextBox, regional: Bool) throws -> [TextBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        request.minimumTextHeight = regional ? 0.003 : 0.01
        request.regionOfInterest = CGRect(x: region.x, y: 1-region.y-region.height, width: region.width, height: region.height)
        try handler.perform([request])
        return (request.results ?? []).compactMap { observation in
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

                guard let projected = VisionRegionRecognition.project(box, into: region) else { return nil }
                var block = TextBlock(
                    box: projected,
                    originalText: candidate.string,
                    confidence: candidate.confidence
                )
                let readings = candidates.map(\.string)
                // Confidence alone is not accuracy. Large lettering with
                // genuinely different optical spellings remains visible for review.
                if languages == ["en-US"], projected.height >= 0.02, projected.y < 0.1, candidate.string.count <= 40,
                   Set(readings.map { $0.uppercased().filter(\.isLetter) }).count > 1 {
                    block.recognitionAlternatives = readings
                }
                return block
        }
    }

    /// Preserve normalized coordinates while giving small English lettering enough pixels.
    private static func enlargedEnglishImage(_ url: URL) throws -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw OCRServiceError.imageDecodeFailed }
        // Large pages are read at full resolution by Vision; check the header before decoding any pixels.
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
           max(width, height) >= 1_000 { return nil }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1_200
              ] as CFDictionary) else { throw OCRServiceError.imageDecodeFailed }
        return try enlargedEnglishImage(image)
    }

    private static func enlargedEnglishImage(_ image: CGImage) throws -> CGImage? {
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
    case imageDecodeFailed, invalidRegions
    public var errorDescription: String? {
        switch self {
        case .imageDecodeFailed: "글자 인식을 위해 이미지를 읽지 못했습니다."
        case .invalidRegions: "글자 인식 영역은 이미지 안의 유효한 범위로 80곳까지 지정할 수 있습니다."
        }
    }
}
