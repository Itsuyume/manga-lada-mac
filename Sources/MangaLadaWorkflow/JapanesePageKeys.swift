import Foundation
import MangaLadaCore

package struct JapanesePageKeys {
    package let translation: String
    package let recognition: String
    package let recognitionBeforeCleanupUpdate: String
    package let reusableRecognition: [String]
    package let previousRecognition: [String]
    package let previous: [String]
    private static let translationVersion = 40
    private static let recognitionVersion = 39
    package init(imageURL: URL, configuration: LocalTranslatorConfiguration, context: String, title: String) throws {
        let fingerprints = ImageFingerprint()
        let image = try fingerprints.make(for: imageURL)
        let oldContext = fingerprints.make(for: Data((title + context.suffix(3_000)).utf8)).prefix(12)
        let newContext = configuration.usesPreviousPageContext ? oldContext : fingerprints.make(for: Data(title.utf8)).prefix(12)
        if configuration.sourceLanguage == .english {
            translation = "\(image)-en-v2-balloons-\(configuration.cacheKey)-\(newContext)"
            recognitionBeforeCleanupUpdate = "\(image)-en-ocr-v2-balloons-ink-v1"
            recognition = "\(image)-en-ocr-v3-balloons-ink-v3"
            reusableRecognition = []
            previousRecognition = ["\(image)-en-ocr-v2-balloons-ink-v3", "\(image)-en-ocr-v2-balloons-ink-v2", recognitionBeforeCleanupUpdate]
            let titleContext = fingerprints.make(for: Data(title.utf8)).prefix(12)
            previous = newContext == titleContext ? [] : ["\(image)-en-v2-balloons-\(configuration.cacheKey)-\(titleContext)"]
            return
        }
        let prefix = "\(image)-jp-"
        let suffix = "balloons-\(configuration.cacheKey)-"
        let ocrSuffix: String
        let priorOCRSuffixes: [String]
        switch configuration.japaneseOCR {
        case .manga:
            ocrSuffix = ""; priorOCRSuffixes = []
        case .hayai:
            ocrSuffix = "-hayai-v3"; priorOCRSuffixes = ["-hayai-v2", "-hayai-v1", ""]
        case .hayaiDetected:
            ocrSuffix = "-hayai-detected-v5"
            priorOCRSuffixes = ["-hayai-detected-v4", "-hayai-detected-v3", "-hayai-detected-v2", "-hayai-detected-v1", "-hayai-v3", "-hayai-v2", "-hayai-v1", ""]
        case .hayaiTextStrokes:
            ocrSuffix = "-hayai-text-strokes-v3"
            priorOCRSuffixes = ["-hayai-text-strokes-v2", "-hayai-text-strokes-v1", "-hayai-detected-v5", "-hayai-detected-v4", "-hayai-detected-v3", "-hayai-detected-v2", "-hayai-detected-v1",
                               "-hayai-v3", "-hayai-v2", "-hayai-v1", ""]
        }
        let baseTranslation = "\(prefix)v\(Self.translationVersion)-\(suffix)\(newContext)"
        // Cleanup has its own key. Keep committed/pending review fingerprints stable.
        translation = baseTranslation + ocrSuffix
        let baseRecognition = prefix + "ocr-v\(Self.recognitionVersion)-balloons"
        recognitionBeforeCleanupUpdate = baseRecognition + ocrSuffix
        recognition = recognitionBeforeCleanupUpdate + "-ink-v5"
        let priorRecognition: [String] = priorOCRSuffixes.flatMap { value in
            let key = baseRecognition + value
            return [key + "-ink-v5", key + "-ink-v4", key + "-ink-v3", key + "-ink-v2", key]
        }
        let olderRecognition = ((Self.recognitionVersion - 3)..<Self.recognitionVersion).reversed().map { prefix + "ocr-v\($0)-balloons" }
        reusableRecognition = [recognitionBeforeCleanupUpdate + "-ink-v4", recognitionBeforeCleanupUpdate + "-ink-v3",
                               recognitionBeforeCleanupUpdate + "-ink-v2", recognitionBeforeCleanupUpdate]
        previousRecognition = reusableRecognition + priorRecognition + olderRecognition
        let contexts = newContext == oldContext ? [newContext] : [newContext, oldContext]
        let olderTranslations: [String] = stride(from: Self.translationVersion - 1, through: 11, by: -1).flatMap { version in
            contexts.map { "\(prefix)v\(version)-\(suffix)\($0)" }
        }
        previous = priorOCRSuffixes.map { baseTranslation + $0 } + olderTranslations
    }
}
