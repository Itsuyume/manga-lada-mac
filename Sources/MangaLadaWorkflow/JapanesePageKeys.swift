import Foundation
import MangaLadaCore

package struct JapanesePageKeys {
    package let translation: String
    package let recognition: String
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
        let ocrSuffix = configuration.japaneseOCR == .hayai ? "-hayai-v2" : ""
        let baseTranslation = "\(prefix)v\(Self.translationVersion)-\(suffix)\(newContext)"
        translation = baseTranslation + ocrSuffix
        let baseRecognition = prefix + "ocr-v\(Self.recognitionVersion)-balloons"
        recognition = baseRecognition + ocrSuffix
        previousRecognition = (ocrSuffix.isEmpty ? [] : [baseRecognition + "-hayai-v1", baseRecognition])
            + ((Self.recognitionVersion - 3)..<Self.recognitionVersion).reversed().map { prefix + "ocr-v\($0)-balloons" }
        let contexts = newContext == oldContext ? [newContext] : [newContext, oldContext]
        let olderTranslations: [String] = stride(from: Self.translationVersion - 1, through: 11, by: -1).flatMap { version in
            contexts.map { "\(prefix)v\(version)-\(suffix)\($0)" }
        }
        previous = (ocrSuffix.isEmpty ? [] : [baseTranslation + "-hayai-v1", baseTranslation]) + olderTranslations
    }
}
