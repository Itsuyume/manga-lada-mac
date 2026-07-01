import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering

@main
struct MangaLadaBallonsChecks {
    @MainActor
    static func main() {
        do {
            let run = try runCheck()
            print("MangaLadaBallonsChecks passed: \(run.blockCount) blocks, \(run.renderedURL.path)")
        } catch {
            fputs("MangaLadaBallonsChecks failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runCheck() throws -> (blockCount: Int, renderedURL: URL) {
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
        guard FileManager.default.fileExists(atPath: result.inpaintedImageURL.path) else {
            throw BallonsCheckError.inpaintedImageMissing(result.inpaintedImageURL)
        }

        let rendered = try TranslatedImageRenderer().writePNG(
            sourceImageURL: result.inpaintedImageURL,
            translation: result.pageTranslation,
            destinationURL: engine.mangaLadaRenderedImageURL(runID: fingerprint),
            backgroundStyle: .none
        )
        guard FileManager.default.fileExists(atPath: rendered.url.path) else {
            throw BallonsCheckError.renderedImageMissing(rendered.url)
        }

        return (rendered.blockCount, rendered.url)
    }

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Manga Lada", isDirectory: true)
    }
}

private enum BallonsCheckError: LocalizedError {
    case missingImageArgument
    case imageMissing(URL)
    case engineMissing(URL)
    case emptyTranslation
    case inpaintedImageMissing(URL)
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
        case .inpaintedImageMissing(let url):
            return "Inpainted Ballons image is missing: \(url.path)"
        case .renderedImageMissing(let url):
            return "Rendered Manga Lada image is missing: \(url.path)"
        }
    }
}
