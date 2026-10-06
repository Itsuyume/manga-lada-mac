import Foundation
import MangaLadaCore
import MangaLadaImport
import MangaLadaRendering
import MangaLadaWorkflow

enum BookTranslationReviews {
    struct Correction: Decodable { let page: Int; let original: String; let translation: String }
    @MainActor
    static func run(source: URL, output: URL, correctionsURL: URL) async throws {
        let support = MangaLadaEdition.applicationSupport
        let inputHash = try ImageFingerprint().make(for: source)
        let input = try await ComicBookLoader(extractionRoot: support.appendingPathComponent("Archives")).load(source)
        let corrections = try JSONDecoder().decode([Correction].self, from: Data(contentsOf: correctionsURL))
        let store = TranslationBookStore()
        let book = try store.prepare(sourceURL: source, title: input.title, pages: input.pages, outputRoot: output)
        let processor = MangaPageProcessor(applicationSupportDirectory: support)
        var applied = 0
        for page in Set(corrections.map(\.page)).sorted() {
            guard input.pages.indices.contains(page - 1) else { throw ReviewError.invalidPage(page) }
            let result = try await processor.process(imageURL: input.pages[page - 1].url, destinationURL: book.pageURL(at: page - 1),
                configuration: LocalTranslatorConfiguration(), typography: MangaTypography(), bookTitle: input.title)
            var edited = result.translation
            for correction in corrections.filter({ $0.page == page }) {
                let matches = edited.blocks.indices.filter { edited.blocks[$0].originalText == correction.original }
                guard matches.count == 1, let index = matches.first, !correction.translation.isEmpty else { throw ReviewError.sourceMismatch(page, correction.original) }
                edited.blocks[index].translatedText = correction.translation
                applied += 1
            }
            _ = try processor.applyEdits(to: result, translation: edited, typography: MangaTypography())
            let reloaded = try await processor.process(imageURL: input.pages[page - 1].url, destinationURL: book.pageURL(at: page - 1),
                configuration: LocalTranslatorConfiguration(), typography: MangaTypography(), previousContext: "Different unused context", bookTitle: input.title)
            guard reloaded.wasCached && reloaded.translation.blocks == edited.blocks else { throw ReviewError.editsLost(page) }
            print("Reviewed page \(page): \(corrections.filter { $0.page == page }.count) corrections; edited text persisted across context changes")
        }
        guard try ImageFingerprint().make(for: source) == inputHash else { throw ReviewError.sourceChanged }
        print("Review checks passed: \(applied) corrections, rendered, cached, source preserved")
    }
    private enum ReviewError: Error { case invalidPage(Int), sourceMismatch(Int, String), editsLost(Int), sourceChanged }
}
