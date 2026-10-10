import AppKit
import Foundation
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

@main
struct MangaLadaWorkflowChecks {
    @MainActor
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.count == 2, arguments[1] == "--cache-migration" {
            try ManualRecognitionChecks.run()
            try CacheMigrationChecks.run()
            try PunctuationReviewChecks.run()
            try await LegacyPunctuationCacheChecks.run()
            try await SupplementalCacheChecks.run()
            return
        }
        if arguments.count == 5, arguments[1] == "--review" {
            try await BookTranslationReviews.run(source: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]),
                                                 correctionsURL: URL(fileURLWithPath: arguments[4]))
            return
        }
        var settings = LocalTranslatorConfiguration(enhanceSoundEffects: arguments.contains("--effects"))
        settings.interpretMaskedText = arguments.contains("--masked-context")
        if let option = arguments.first(where: { $0.hasPrefix("--source=") }) {
            guard let language = LanguageCode(rawValue: String(option.dropFirst(9))) else { throw CheckFailure.invalidOCR }
            try language.validateComicSource()
            settings.sourceLanguage = language
        }
        if let option = arguments.first(where: { $0.hasPrefix("--model=") }) { settings.ollama.model = String(option.dropFirst(8)) }
        if let option = arguments.first(where: { $0.hasPrefix("--ocr=") }) {
            guard let backend = JapaneseOCRBackend(rawValue: String(option.dropFirst(6))) else { throw CheckFailure.invalidOCR }
            settings.japaneseOCR = backend
        }
        if arguments.count >= 5, arguments[1] == "--real-regression" {
            do {
                try await RealPageRegressionChecks.run(manifest: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]),
                    support: URL(fileURLWithPath: arguments[4]), configuration: settings)
            } catch {
                FileHandle.standardError.write(Data("Real-page regression failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        if arguments.count >= 4, arguments[1] == "--text-benchmark" {
            do {
                try await TextTranslationBenchmark.run(input: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]), configuration: settings)
            } catch {
                FileHandle.standardError.write(Data("Text benchmark failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
            return
        }
        if arguments.count >= 4, arguments[1] == "--book" {
            try await BookTranslationChecks.run(source: URL(fileURLWithPath: arguments[2]), output: URL(fileURLWithPath: arguments[3]), configuration: settings)
            return
        }
        guard arguments.count >= 3 else {
            print("Usage: MangaLadaWorkflowChecks <source-image> <output.png> [--source=ja|en]")
            exit(1)
        }
        let source = URL(fileURLWithPath: arguments[1])
        let output = URL(fileURLWithPath: arguments[2])
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Manga Lada")
        let original = try Data(contentsOf: source)
        let processor = MangaPageProcessor(applicationSupportDirectory: support)
        let bookTitle = arguments.dropFirst(3).first { !$0.hasPrefix("--") } ?? ""
        if let region = arguments.first(where: { $0.hasPrefix("--region=") }) {
            let values = region.dropFirst(9).split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { throw CheckFailure.invalidRegion }
            try await ManualRegionChecks.run(source: source, output: output,
                box: TextBox(x: values[0], y: values[1], width: values[2], height: values[3]), title: bookTitle, configuration: settings)
            return
        }
        let result = try await processor.process(imageURL: source, destinationURL: output,
                                                 configuration: settings, typography: MangaTypography(), bookTitle: bookTitle) { print($0) }
        guard original == (try Data(contentsOf: source)) else { throw CheckFailure.sourceChanged }
        guard !result.translation.blocks.isEmpty else { throw CheckFailure.noText }
        guard result.translation.blocks.allSatisfy({ !$0.translatedText.isEmpty }) else { throw CheckFailure.missingTranslation }
        let cached = try await processor.process(imageURL: source, destinationURL: output,
                                                 configuration: settings, typography: MangaTypography(), bookTitle: bookTitle)
        guard cached.wasCached && cached.translation.blocks == result.translation.blocks else { throw CheckFailure.cacheMismatch }
        guard NSImage(contentsOf: output) != nil else { throw CheckFailure.invalidPNG }
        for block in result.translation.blocks {
            print("\(block.textKind?.rawValue ?? "dialogue"): \(block.originalText.replacingOccurrences(of: "\n", with: " ")) -> \(block.translatedText) [shape=\(block.balloonShape != nil)]")
        }
        for warning in result.warnings { print("WARNING: \(warning)") }
        print("MangaLadaWorkflowChecks passed: \(result.translation.blocks.count) regions, local only, source preserved, cache reused")
    }
}

private enum CheckFailure: Error {
    case sourceChanged, noText, missingTranslation, cacheMismatch, invalidPNG, invalidRegion, invalidOCR
}
