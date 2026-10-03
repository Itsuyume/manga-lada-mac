import Foundation
import MangaLadaCore

struct JapanesePageKeys {
    let translation: String
    let recognition: String
    let previousRecognition: [String]
    let previous: [String]
    private static let translationVersion = 19
    private static let recognitionVersion = 18
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
        previous = [prefix + "v18-" + suffix + newContext, prefix + "v18-" + suffix + oldContext,
                    prefix + "v17-" + suffix + newContext, prefix + "v17-" + suffix + oldContext,
                    prefix + "v16-" + suffix + newContext, prefix + "v16-" + suffix + oldContext,
                    prefix + "v15-" + suffix + newContext, prefix + "v15-" + suffix + oldContext,
                    prefix + "v14-" + suffix + newContext, prefix + "v14-" + suffix + oldContext, prefix + "v13-" + suffix + newContext,
                    prefix + "v13-" + suffix + oldContext, prefix + "v12-" + suffix + newContext,
                    prefix + "v12-" + suffix + oldContext, prefix + "v11-" + suffix + oldContext]
    }
}

struct MangaPageDraft {
    var translation: PageTranslation
    let cleanImageURL: URL
    let wasCached: Bool
}
