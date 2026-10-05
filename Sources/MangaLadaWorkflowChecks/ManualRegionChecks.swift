import AppKit
import Foundation
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

@MainActor
enum ManualRegionChecks {
    static func run(source: URL, output: URL, box: TextBox, title: String, configuration: LocalTranslatorConfiguration) async throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manga Lada")
        let processor = MangaPageProcessor(applicationSupportDirectory: support)
        let bytes = try Data(contentsOf: source)
        let before = try await processor.process(imageURL: source, destinationURL: output, configuration: configuration,
            typography: MangaTypography(), bookTitle: title)
        let replaced = before.translation.blocks.filter { ImageRegionSelection.containsCenter(box, of: $0.box) }
        let result = try await processor.translateRegion(imageURL: source, destinationURL: output, box: box, kind: .dialogue,
            configuration: configuration, typography: MangaTypography(), bookTitle: title) { print($0) }
        let selected = result.translation.blocks.filter { $0.userDefinedBounds != nil && ImageRegionSelection.containsCenter(box, of: $0.box) }
        guard selected.count == max(1, replaced.count), selected.allSatisfy({ !$0.translatedText.isEmpty }), NSImage(contentsOf: output) != nil else {
            throw ManualCheckFailure.failed("Manual regions did not render separately.")
        }
        if !replaced.isEmpty {
            guard Set(selected.map(\.id)) == Set(replaced.map(\.id)), result.translation.blocks.count == before.translation.blocks.count else {
                throw ManualCheckFailure.failed("Numbered region identities or count changed.")
            }
        }
        let untouched = before.translation.blocks.filter { !ImageRegionSelection.containsCenter(box, of: $0.box) }
        guard untouched.allSatisfy({ result.translation.blocks.contains($0) }) else { throw ManualCheckFailure.failed("Unselected text changed.") }
        for block in selected where TextLanguageDetector.isPunctuationOnly(block.originalText) {
            guard block.verifiedPunctuationBounds != nil, block.userDefinedOriginalText == false else {
                throw ManualCheckFailure.failed("Manual punctuation lost its verified source bounds.")
            }
        }
        let reloaded = try await processor.process(imageURL: source, destinationURL: output, configuration: configuration,
            typography: MangaTypography(), previousContext: "context changed", bookTitle: title)
        guard reloaded.wasCached, reloaded.translation.blocks == result.translation.blocks else { throw ManualCheckFailure.failed("Manual bounds/text were lost after reload.") }
        guard bytes == (try Data(contentsOf: source)) else { throw ManualCheckFailure.failed("Manual selection modified the source image.") }
        let saved = try Data(contentsOf: output)
        do {
            _ = try await processor.translateRegion(imageURL: source, destinationURL: output, box: TextBox(x: -0.1, y: 0, width: 0.1, height: 0.1),
                kind: .dialogue, configuration: configuration, typography: MangaTypography(), bookTitle: title)
            throw ManualCheckFailure.failed("Invalid selection was accepted.")
        } catch ManualRegionError.invalidBounds { }
        guard saved == (try Data(contentsOf: output)) else { throw ManualCheckFailure.failed("Rejected region modified the saved result.") }
        let forced = try await processor.process(imageURL: source, destinationURL: output, configuration: configuration,
            typography: MangaTypography(), bookTitle: title, force: true)
        guard selected.allSatisfy({ prior in forced.translation.blocks.contains { updated in
            updated.id == prior.id && updated.userDefinedBounds == prior.userDefinedBounds && updated.textKind == prior.textKind
                && updated.userDefinedTextKind == true && updated.originalText == prior.originalText
                && updated.verifiedPunctuationBounds == prior.verifiedPunctuationBounds
        } }) else { throw ManualCheckFailure.failed("Explicit retranslating lost manual bounds, identities, source text or chosen kind.") }
        guard bytes == (try Data(contentsOf: source)) else { throw ManualCheckFailure.failed("Retranslating modified the source image.") }
        for block in selected { print("Manual: \(block.originalText) -> \(block.translatedText)") }
        print("Manual selection passed: \(selected.count) separate regions, IDs/count preserved, unselected text and source unchanged, reload retained bounds/text, rejected input had no side effects, explicit retranslation retained manual identities/bounds/kind/source")
    }
}
private enum ManualCheckFailure: Error { case failed(String) }
