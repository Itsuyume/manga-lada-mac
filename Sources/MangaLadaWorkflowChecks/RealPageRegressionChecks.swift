import Foundation
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

/// Runs annotated real pages through the shipping processor and retains failures for visual review.
enum RealPageRegressionChecks {
    struct Fixture: Decodable {
        let id: String
        let image: String
        let expected: [Expectation]
        let expectsNoText: Bool?
        let requiresWarning: Bool?
        let sourceLanguage: LanguageCode?
    }
    struct Expectation: Decodable {
        let original: String
        let koreanContainsAny: [String]?
        let forbiddenKorean: [String]?
        let kind: MangaTextKind?
        let requiresShape: Bool?
    }
    private struct Result: Encodable {
        let id: String
        let elapsed: Double
        let sourcePreserved: Bool
        let cacheReused: Bool
        let errors: [String]
        let warnings: [String]
        let blocks: [TextBlock]
        let sourceLanguage: LanguageCode?
    }

    @MainActor
    static func run(manifest: URL, output: URL, support: URL, configuration: LocalTranslatorConfiguration) async throws {
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.outputExists }
        let source = try Data(contentsOf: manifest)
        let fixtures = try JSONDecoder().decode([Fixture].self, from: source)
        guard !fixtures.isEmpty, Set(fixtures.map(\.id)).count == fixtures.count,
              fixtures.allSatisfy({ !$0.id.isEmpty && !$0.id.contains("/") && (!$0.expected.isEmpty || $0.expectsNoText == true)
                  && $0.expected.allSatisfy({ !$0.original.isEmpty }) }) else { throw Failure.invalidManifest }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let processor = MangaPageProcessor(applicationSupportDirectory: support)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var results: [Result] = []
        for fixture in fixtures {
            try Task.checkCancellation()
            let image = manifest.deletingLastPathComponent().appendingPathComponent(fixture.image)
            let result = try await evaluate(fixture, image: image, output: output, processor: processor, configuration: configuration)
            results.append(result)
            try encoder.encode(results).write(to: output.appendingPathComponent("regression-results.json"), options: .atomic)
            print("\(fixture.id): \(result.errors.isEmpty ? "PASS" : "FAIL") · \(result.blocks.count) regions · \(String(format: "%.1f", result.elapsed))s")
            for error in result.errors { print("  \(error)") }
            fflush(stdout)
        }
        guard source == (try Data(contentsOf: manifest)) else { throw Failure.sourceChanged }
        guard results.allSatisfy({ $0.errors.isEmpty }) else { throw Failure.failedCases }
        print("Annotated real-page checks passed. Inspect saved PNGs separately; these assertions do not prove every translation correct.")
    }

    @MainActor
    private static func evaluate(_ fixture: Fixture, image: URL, output: URL, processor: MangaPageProcessor,
                                 configuration: LocalTranslatorConfiguration) async throws -> Result {
        let original = try Data(contentsOf: image), began = Date()
        let destination = output.appendingPathComponent(fixture.id + ".png")
        var blocks: [TextBlock] = [], errors: [String] = [], warnings: [String] = [], reused = false
        var language: LanguageCode?
        do {
            let result = try await processor.process(imageURL: image, destinationURL: destination,
                configuration: configuration, typography: MangaTypography())
            blocks = result.translation.blocks
            language = result.translation.sourceLanguage
            warnings = result.reviewWarnings
            let saved = try Data(contentsOf: destination)
            let cached = try await processor.process(imageURL: image, destinationURL: destination,
                configuration: configuration, typography: MangaTypography())
            let cachedBytes = try Data(contentsOf: destination)
            reused = cached.wasCached && cached.translation.blocks == blocks && cached.reviewWarnings == warnings && saved == cachedBytes
                && cached.translation.sourceLanguage == language
            if !reused { errors.append("Cache reuse changed regions or saved pixels") }
        } catch let failure as MangaPageFailure {
            blocks = failure.draft.translation.blocks
            language = failure.draft.translation.sourceLanguage
            errors.append(failure.localizedDescription)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            errors.append(error.localizedDescription)
        }
        let preserved = try original == Data(contentsOf: image)
        if !preserved { errors.append("Source image changed") }
        errors += mismatches(fixture.expected, blocks: blocks)
        if fixture.expectsNoText == true, !blocks.isEmpty { errors.append("A textless page acquired invented regions") }
        if fixture.requiresWarning == true, warnings.isEmpty { errors.append("Unresolved recognition lost its visible review warning") }
        if let expected = fixture.sourceLanguage, expected != language { errors.append("Wrong page language: expected \(expected.rawValue)") }
        return Result(id: fixture.id, elapsed: Date().timeIntervalSince(began), sourcePreserved: preserved,
                      cacheReused: reused, errors: errors, warnings: warnings, blocks: blocks, sourceLanguage: language)
    }

    static func mismatches(_ expected: [Expectation], blocks: [TextBlock]) -> [String] {
        expected.flatMap { item -> [String] in
            let matches = blocks.filter { $0.originalText.filter { !$0.isWhitespace }.contains(item.original.filter { !$0.isWhitespace }) }
            guard matches.count == 1, let block = matches.first else { return ["Missing or ambiguous OCR: \(item.original)"] }
            var errors: [String] = []
            if let words = item.koreanContainsAny, !words.contains(where: { block.translatedText.contains($0) }) {
                errors.append("Meaning check failed: \(item.original) → \(block.translatedText)")
            }
            if let words = item.forbiddenKorean, words.contains(where: { block.translatedText.contains($0) }) {
                errors.append("Previous wrong translation returned: \(item.original) → \(block.translatedText)")
            }
            if let kind = item.kind, block.textKind != kind { errors.append("Wrong region kind: \(item.original)") }
            if item.requiresShape == true, block.balloonShape == nil { errors.append("Missing balloon outline: \(item.original)") }
            return errors
        }
    }

    private enum Failure: Error { case outputExists, invalidManifest, sourceChanged, failedCases }
}
