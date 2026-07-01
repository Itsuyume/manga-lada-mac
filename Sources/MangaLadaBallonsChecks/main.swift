import Foundation
import MangaLadaBallons
import MangaLadaCore

enum BallonsCheckError: LocalizedError {
    case missingImageArgument
    case imageMissing(URL)
    case engineMissing(URL)
    case emptyTranslation
    case renderedImageMissing(URL)

    var errorDescription: String? {
        switch self {
        case .missingImageArgument:
            return "Usage: swift run MangaLadaBallonsChecks /path/to/page.png"
        case .imageMissing(let url):
            return "Image does not exist: \(url.path)"
        case .engineMissing(let url):
            return "Ballons engine is not installed at: \(url.path)"
        case .emptyTranslation:
            return "Ballons returned no translation blocks."
        case .renderedImageMissing(let url):
            return "Rendered Ballons image is missing: \(url.path)"
        }
    }
}

func applicationSupportDirectory() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("Manga Lada", isDirectory: true)
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw BallonsCheckError.missingImageArgument
    }

    let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        throw BallonsCheckError.imageMissing(imageURL)
    }

    let engine = BallonsTranslatorEngine.standard(applicationSupportDirectory: applicationSupportDirectory())
    guard engine.isInstalled else {
        throw BallonsCheckError.engineMissing(engine.sourceRootURL)
    }

    let fingerprint = try ImageFingerprint().make(for: imageURL) + "-ballons-check"
    try engine.clearRun(runID: fingerprint)
    let result = try engine.translate(
        sourceImageURL: imageURL,
        runID: fingerprint,
        imageFingerprint: fingerprint
    )

    guard !result.pageTranslation.blocks.isEmpty else {
        throw BallonsCheckError.emptyTranslation
    }
    guard FileManager.default.fileExists(atPath: result.renderedImageURL.path) else {
        throw BallonsCheckError.renderedImageMissing(result.renderedImageURL)
    }

    print(
        "MangaLadaBallonsChecks passed: \(result.pageTranslation.blocks.count) blocks, \(result.renderedImageURL.path)"
    )
} catch {
    fputs("MangaLadaBallonsChecks failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
