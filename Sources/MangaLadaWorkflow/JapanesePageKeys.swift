import Foundation
import MangaLadaCore

package struct JapanesePageKeys {
    package let translation: String
    package let recognition: String
    package let recognitionBeforeCleanupUpdate: String
    package let previousRecognition: [String]
    package let previous: [String]
    private static let translationVersion = 40
    private static let recognitionVersion = 39
    package init(imageURL: URL, configuration: LocalTranslatorConfiguration, context: String, title: String) throws {
        let fingerprints = ImageFingerprint()
        let image = try fingerprints.make(for: imageURL)
        let oldContext = fingerprints.make(for: Data((title + context.suffix(3_000)).utf8)).prefix(12)
        let newContext = configuration.usesPreviousPageContext ? oldContext : fingerprints.make(for: Data(title.utf8)).prefix(12)
        let prefix = "\(image)-jp-"
        let suffix = "balloons-\(configuration.cacheKey)-"
        let ocrSuffix: String
        switch configuration.japaneseOCR {
        case .manga: ocrSuffix = ""
        case .hayai: ocrSuffix = "-hayai-v2"
        case .hayaiDetected: ocrSuffix = "-hayai-detected-v1"
        }
        let baseTranslation = "\(prefix)v\(Self.translationVersion)-\(suffix)\(newContext)"
        // Cleanup has its own key. Keep committed/pending review fingerprints stable.
        translation = baseTranslation + ocrSuffix
        let baseRecognition = prefix + "ocr-v\(Self.recognitionVersion)-balloons"
        recognitionBeforeCleanupUpdate = baseRecognition + ocrSuffix
        recognition = recognitionBeforeCleanupUpdate + "-ink-v2"
        let priorHayai = configuration.japaneseOCR == .hayaiDetected ? ["-hayai-v2-ink-v2", "-hayai-v2"] : []
        previousRecognition = [recognitionBeforeCleanupUpdate] + priorHayai.map { baseRecognition + $0 }
            + (ocrSuffix.isEmpty ? [] : [baseRecognition + "-hayai-v1", baseRecognition])
            + ((Self.recognitionVersion - 3)..<Self.recognitionVersion).reversed().map { prefix + "ocr-v\($0)-balloons" }
        let contexts = newContext == oldContext ? [newContext] : [newContext, oldContext]
        let olderTranslations: [String] = stride(from: Self.translationVersion - 1, through: 11, by: -1).flatMap { version in
            contexts.map { "\(prefix)v\(version)-\(suffix)\($0)" }
        }
        previous = (configuration.japaneseOCR == .hayaiDetected ? [baseTranslation + "-hayai-v2"] : [])
            + (ocrSuffix.isEmpty ? [] : [baseTranslation + "-hayai-v1", baseTranslation]) + olderTranslations
    }
}
