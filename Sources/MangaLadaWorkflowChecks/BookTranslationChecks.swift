import AppKit
import Foundation
import MangaLadaCore
import MangaLadaImport
import MangaLadaRendering
import MangaLadaWorkflow

enum BookTranslationChecks {
    @MainActor
    static func run(source: URL, output: URL, configuration: LocalTranslatorConfiguration = LocalTranslatorConfiguration()) async throws {
        let began = Date()
        let support = MangaLadaEdition.applicationSupport
        let original = try sourceFingerprints(source)
        let loader = ComicBookLoader(extractionRoot: support.appendingPathComponent("Archives"))
        let input = try await loader.load(source)
        let store = TranslationBookStore()
        var book = try store.prepare(sourceURL: source, title: input.title, pages: input.pages, outputRoot: output)
        let processor = MangaPageProcessor(applicationSupportDirectory: support)
        var context = "", reports: [PageReport] = []
        for index in input.pages.indices {
            let pageBegan = Date()
            do {
                let result = try await processor.process(imageURL: input.pages[index].url, destinationURL: book.pageURL(at: index),
                                                         configuration: configuration, typography: MangaTypography(),
                                                         previousContext: context, bookTitle: input.title)
                guard let rendered = NSImage(contentsOf: result.renderedImageURL), let sourceImage = NSImage(contentsOf: input.pages[index].url),
                      rendered.representations[0].pixelsWide == sourceImage.representations[0].pixelsWide,
                      rendered.representations[0].pixelsHigh == sourceImage.representations[0].pixelsHigh else { throw BookCheckError.invalidDimensions }
                context = result.translation.blocks.map { "\($0.originalText): \($0.translatedText)" }.joined(separator: "\n")
                book.manifest.completedPages.append(index); book.manifest.failures.removeValue(forKey: index)
                reports.append(PageReport(page: index + 1, regions: result.translation.blocks.count,
                                           shaped: result.translation.blocks.filter { $0.balloonShape != nil }.count,
                                           elapsed: Date().timeIntervalSince(pageBegan), failure: nil))
                print("\(index + 1)/\(input.pages.count): saved \(result.translation.blocks.count) regions, \(String(format: "%.1f", Date().timeIntervalSince(pageBegan)))s")
            } catch {
                book.manifest.failures[index] = error.localizedDescription
                reports.append(PageReport(page: index + 1, regions: 0, shaped: 0, elapsed: Date().timeIntervalSince(pageBegan), failure: error.localizedDescription))
                print("\(index + 1)/\(input.pages.count): FAILED: \(error.localizedDescription)")
            }
            book.manifest.completedPages = Array(Set(book.manifest.completedPages)).sorted()
            try store.save(book)
            fflush(stdout)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = Report(pages: reports, elapsed: Date().timeIntervalSince(began), sourcePreserved: try sourceFingerprints(source) == original)
        try encoder.encode(report).write(to: output.appendingPathComponent("translation-checks.json"), options: .atomic)
        guard report.sourcePreserved else { throw BookCheckError.sourceChanged }
        guard book.manifest.failures.isEmpty else { throw BookCheckError.failedPages(book.manifest.failures.count) }
        print("Book checks passed: \(reports.count) pages, source preserved, \(String(format: "%.1f", report.elapsed))s")
    }
    private static func sourceFingerprints(_ source: URL) throws -> [URL: String] {
        let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        let files = isDirectory ? try ImageFileScanner().images(in: source, recursive: true).map(\.url) : [source]
        let fingerprint = ImageFingerprint()
        return try Dictionary(uniqueKeysWithValues: files.map { ($0, try fingerprint.make(for: $0)) })
    }
    private struct PageReport: Encodable { let page: Int; let regions: Int; let shaped: Int; let elapsed: Double; let failure: String? }
    private struct Report: Encodable { let pages: [PageReport]; let elapsed: Double; let sourcePreserved: Bool }
    private enum BookCheckError: Error { case sourceChanged, invalidDimensions, failedPages(Int) }
}
