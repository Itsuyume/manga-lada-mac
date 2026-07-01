import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering

@main
struct MangaLadaBallonsChecks {
    @MainActor
    static func main() async {
        do {
            let run = try await runCheck()
            print("MangaLadaBallonsChecks passed: \(run.blockCount) blocks, \(run.renderedURL.path)")
        } catch {
            fputs("MangaLadaBallonsChecks failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runCheck() async throws -> (blockCount: Int, renderedURL: URL) {
        let options = try BallonsCheckOptions.parse(CommandLine.arguments)
        let imageURL = URL(fileURLWithPath: options.imagePath)
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
            imageFingerprint: fingerprint,
            enableTranslation: options.usesBallonsTranslation
        )

        guard !result.pageTranslation.blocks.isEmpty else {
            throw BallonsCheckError.emptyTranslation
        }
        guard FileManager.default.fileExists(atPath: result.inpaintedImageURL.path) else {
            throw BallonsCheckError.inpaintedImageMissing(result.inpaintedImageURL)
        }

        let translation = try await translationForRendering(result.pageTranslation, options: options)
        let rendered = try TranslatedImageRenderer().writePNG(
            sourceImageURL: result.inpaintedImageURL,
            translation: translation,
            destinationURL: engine.mangaLadaRenderedImageURL(runID: fingerprint),
            backgroundStyle: .readabilityBubble
        )
        guard FileManager.default.fileExists(atPath: rendered.url.path) else {
            throw BallonsCheckError.renderedImageMissing(rendered.url)
        }

        return (rendered.blockCount, rendered.url)
    }

    private static func translationForRendering(
        _ translation: PageTranslation,
        options: BallonsCheckOptions
    ) async throws -> PageTranslation {
        if options.useGoogle {
            return try await localTranslation(translation)
        }
        if options.ocrOnly {
            return passthroughTranslation(translation)
        }
        return translation
    }

    private static func localTranslation(
        _ translation: PageTranslation
    ) async throws -> PageTranslation {
        let configuration = try LocalTranslatorConfiguration.load(configURL: translatorConfigURL())
        let pipeline = TranslationPipeline(
            sourceLanguage: translation.sourceLanguage,
            targetLanguage: translation.targetLanguage
        )
        let blocks = try await pipeline.translate(
            translation.blocks,
            configuration: configuration
        )
        guard blocks.contains(where: { containsHangul($0.translatedText) }) else {
            throw BallonsCheckError.missingKoreanOutput
        }
        return PageTranslation(
            imageURL: translation.imageURL,
            imageFingerprint: translation.imageFingerprint,
            sourceLanguage: translation.sourceLanguage,
            targetLanguage: translation.targetLanguage,
            createdAt: translation.createdAt,
            blocks: blocks
        )
    }

    private static func passthroughTranslation(_ translation: PageTranslation) -> PageTranslation {
        PageTranslation(
            imageURL: translation.imageURL,
            imageFingerprint: translation.imageFingerprint,
            sourceLanguage: translation.sourceLanguage,
            targetLanguage: translation.targetLanguage,
            createdAt: translation.createdAt,
            blocks: translation.blocks.map { block in
                var passthroughBlock = block
                passthroughBlock.translatedText = block.originalText
                return passthroughBlock
            }
        )
    }

    private static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(Int(scalar.value))
        }
    }

    private static func translatorConfigURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("translator.local.json")
    }

    private static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Manga Lada", isDirectory: true)
    }
}

private struct BallonsCheckOptions {
    let imagePath: String
    let ocrOnly: Bool
    let useGoogle: Bool

    var usesBallonsTranslation: Bool {
        !useGoogle && !ocrOnly
    }

    static func parse(_ arguments: [String]) throws -> BallonsCheckOptions {
        var imagePath: String?
        var ocrOnly = false
        var useGoogle = false
        var index = 1

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--ocr-only" {
                ocrOnly = true
                index += 1
                continue
            }
            if argument == "--google" {
                useGoogle = true
                index += 1
                continue
            }
            if argument == "--local-provider" {
                let providerIndex = index + 1
                guard providerIndex < arguments.count else {
                    throw BallonsCheckError.missingProviderValue
                }
                guard arguments[providerIndex] == TranslationProvider.googleWeb.rawValue else {
                    throw BallonsCheckError.invalidProvider(arguments[providerIndex])
                }
                useGoogle = true
                index += 2
                continue
            }
            guard imagePath == nil else {
                throw BallonsCheckError.missingImageArgument
            }
            imagePath = argument
            index += 1
        }

        guard let imagePath else {
            throw BallonsCheckError.missingImageArgument
        }
        return BallonsCheckOptions(imagePath: imagePath, ocrOnly: ocrOnly, useGoogle: useGoogle)
    }
}

private enum BallonsCheckError: LocalizedError {
    case missingImageArgument
    case missingProviderValue
    case invalidProvider(String)
    case imageMissing(URL)
    case engineMissing(URL)
    case emptyTranslation
    case missingKoreanOutput
    case inpaintedImageMissing(URL)
    case renderedImageMissing(URL)

    var errorDescription: String? {
        switch self {
        case .missingImageArgument:
            return "Usage: swift run MangaLadaBallonsChecks [--ocr-only] [--google] /path/to/page.png"
        case .missingProviderValue:
            return "--local-provider requires a provider raw value, for example: google_web"
        case .invalidProvider(let provider):
            return "Unknown local provider: \(provider)"
        case .imageMissing(let url):
            return "Image does not exist: \(url.path)"
        case .engineMissing(let url):
            return "Ballons engine is not installed at: \(url.path)"
        case .emptyTranslation:
            return "Ballons returned no translation blocks."
        case .missingKoreanOutput:
            return "Google did not return Korean text."
        case .inpaintedImageMissing(let url):
            return "Inpainted Ballons image is missing: \(url.path)"
        case .renderedImageMissing(let url):
            return "Rendered Manga Lada image is missing: \(url.path)"
        }
    }
}
