import Foundation
import MangaLadaBallons
import MangaLadaCore

/// Runs the production resident worker without a translation request or rendered page.
enum OCRSessionCheck {
    static func run(_ arguments: [String]) async throws {
        guard arguments.count == 6, let backend = JapaneseOCRBackend(rawValue: arguments[2]),
              ["crop", "page", "reread"].contains(arguments[3]) else {
            throw Failure.invalidArguments
        }
        let source = URL(fileURLWithPath: arguments[4]), output = URL(fileURLWithPath: arguments[5])
        guard !FileManager.default.fileExists(atPath: output.path) else { throw CocoaError(.fileWriteFileExists) }
        let before = try Data(contentsOf: source)
        let support = MangaLadaEdition.applicationSupport
        let engine = BallonsTranslatorEngine.standard(applicationSupportDirectory: support)
        let session = JapaneseEngineSession(engine: engine)
        let id = "ocr-session-" + UUID().uuidString
        let region = TextBlock(box: .init(x: 0, y: 0, width: 1, height: 1), originalText: "stale OCR")
        let page: PageTranslation
        var rereadIDs = Set<UUID>()
        do {
            if arguments[3] == "crop" {
                let blocks = try await session.verifyProposedRegions(source: source, regions: [region], ocrBackend: backend)
                page = PageTranslation(imageURL: source, imageFingerprint: id, sourceLanguage: .japanese, targetLanguage: .korean, blocks: blocks)
            } else {
                var prior: [TextBlock]?
                if arguments[3] == "reread" {
                    let baseline = try await session.recognizeAndClean(source: source, runID: id + "-baseline")
                    guard !baseline.blocks.isEmpty else { throw Failure.missingBaseline }
                    prior = baseline.blocks.map { block in
                        var old = block; old.originalText = region.originalText; return old
                    }
                    rereadIDs = Set(baseline.blocks.map(\.id))
                }
                page = try await session.recognizeAndClean(source: source, runID: id,
                    priorBlocks: prior, ocrBackend: backend,
                    rereadExisting: arguments[3] == "reread")
            }
            await session.stop()
        } catch {
            await session.stop()
            throw error
        }
        guard try Data(contentsOf: source) == before else { throw Failure.sourceChanged }
        guard page.blocks.allSatisfy({ $0.translatedText.isEmpty }) else { throw Failure.unexpectedTranslation }
        if arguments[3] == "reread" {
            guard rereadIDs.isSubset(of: Set(page.blocks.map(\.id))),
                  page.blocks.allSatisfy({ $0.originalText != region.originalText }) else {
                throw Failure.staleOCR
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let report = Report(ocrBackend: backend, mode: arguments[3], sourcePreserved: true, page: page,
                            cleanImage: arguments[3] == "crop" ? nil : engine.inpaintedImageURL(runID: id))
        try encoder.encode(report).write(to: output, options: .withoutOverwriting)
        print("OCR session: \(page.blocks.count) regions, \(page.blocks.filter { $0.recognitionAlternatives != nil }.count) need review; source unchanged; no translation")
    }

    private struct Report: Encodable {
        let ocrBackend: JapaneseOCRBackend
        let mode: String
        let sourcePreserved: Bool
        let page: PageTranslation
        let cleanImage: URL?
    }
    private enum Failure: Error { case invalidArguments, sourceChanged, unexpectedTranslation, staleOCR, missingBaseline }
}
