import Foundation
import MangaLadaCore

package struct JapanesePageKeys {
    package let translation: String
    package let recognition: String
    let previousRecognition: [String]
    let previous: [String]
    private static let translationVersion = 40
    private static let recognitionVersion = 39
    package init(imageURL: URL, configuration: LocalTranslatorConfiguration, context: String, title: String) throws {
        let fingerprints = ImageFingerprint()
        let image = try fingerprints.make(for: imageURL)
        let oldContext = fingerprints.make(for: Data((title + context.suffix(3_000)).utf8)).prefix(12)
        let newContext = configuration.usesPreviousPageContext ? oldContext : fingerprints.make(for: Data(title.utf8)).prefix(12)
        let prefix = "\(image)-jp-"
        let suffix = "balloons-\(configuration.cacheKey)-"
        let ocrSuffix = configuration.japaneseOCR == .hayai ? "-hayai-v1" : ""
        translation = prefix + "v\(Self.translationVersion)-" + suffix + newContext + ocrSuffix
        let baseRecognition = prefix + "ocr-v\(Self.recognitionVersion)-balloons"
        recognition = baseRecognition + ocrSuffix
        previousRecognition = (ocrSuffix.isEmpty ? [] : [baseRecognition])
            + ((Self.recognitionVersion - 3)..<Self.recognitionVersion).reversed().map { prefix + "ocr-v\($0)-balloons" }
        let contexts = newContext == oldContext ? [newContext] : [newContext, oldContext]
        previous = (ocrSuffix.isEmpty ? [] : [prefix + "v\(Self.translationVersion)-" + suffix + newContext])
            + stride(from: Self.translationVersion - 1, through: 11, by: -1).flatMap { version in
            contexts.map { prefix + "v\(version)-" + suffix + $0 }
        }
    }
}
