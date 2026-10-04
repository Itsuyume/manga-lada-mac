import Foundation
import MangaLadaCore
import MangaLadaRendering

@MainActor
package enum PageImageRendering {
    package static func render(translation: PageTranslation, cleanImageURL: URL, destinationURL: URL,
                       typography: MangaTypography, wasCached: Bool) throws -> ProcessedMangaPage {
        if translation.blocks.isEmpty {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contentsOf: cleanImageURL).write(to: destinationURL, options: .atomic)
        } else {
            _ = try TranslatedImageRenderer(typography: typography).writePNG(
                sourceImageURL: cleanImageURL, translation: translation, destinationURL: destinationURL,
                fontScale: typography.fontScale, backgroundStyle: .none, originalImageURL: translation.imageURL
            )
        }
        return ProcessedMangaPage(translation: translation, cleanImageURL: cleanImageURL,
                                  renderedImageURL: destinationURL, wasCached: wasCached)
    }
}
