import Foundation
import MangaLadaCore

struct JapanesePageKeys {
    let translation: String
    let recognition: String
    let previousRecognition: [String]
    let previous: [String]
    private static let translationVersion = 26
    private static let recognitionVersion = 25
    init(imageURL: URL, configuration: LocalTranslatorConfiguration, context: String, title: String) throws {
        let fingerprints = ImageFingerprint()
        let image = try fingerprints.make(for: imageURL)
        let oldContext = fingerprints.make(for: Data((title + context.suffix(3_000)).utf8)).prefix(12)
        let newContext = configuration.usesPreviousPageContext ? oldContext : fingerprints.make(for: Data(title.utf8)).prefix(12)
        let prefix = "\(image)-jp-"
        let suffix = "balloons-\(configuration.cacheKey)-"
        translation = prefix + "v\(Self.translationVersion)-" + suffix + newContext
        recognition = prefix + "ocr-v\(Self.recognitionVersion)-balloons"
        previousRecognition = ((Self.recognitionVersion - 3)..<Self.recognitionVersion).reversed().map { prefix + "ocr-v\($0)-balloons" }
        let contexts = newContext == oldContext ? [newContext] : [newContext, oldContext]
        previous = stride(from: Self.translationVersion - 1, through: 11, by: -1).flatMap { version in
            contexts.map { prefix + "v\(version)-" + suffix + $0 }
        }
    }
}

struct MangaPageDraft {
    var translation: PageTranslation
    let cleanImageURL: URL
    let wasCached: Bool
}
