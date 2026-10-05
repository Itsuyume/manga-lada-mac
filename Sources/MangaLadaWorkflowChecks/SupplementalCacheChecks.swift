import AppKit
import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering
import MangaLadaWorkflow

@MainActor
enum SupplementalCacheChecks {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SupplementalCacheChecks/\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png"), output = root.appendingPathComponent("result.png")
        guard let bitmap = NSBitmapImageRep(data: PunctuationReviewChecks.image(cleaned: true).tiffRepresentation!),
              let pixels = bitmap.representation(using: .png, properties: [:]) else { throw Failure.image }
        try pixels.write(to: source)
        let configuration = LocalTranslatorConfiguration(provider: .geminiFlashLite, enhanceSoundEffects: true)
        let keys = try JapanesePageKeys(imageURL: source, configuration: configuration, context: "", title: "")
        let effect = TextBlock(box: .init(x: 0.2, y: 0.2, width: 0.5, height: 0.3), originalText: "カチッ",
            translatedText: "대사로 잘못 저장", textKind: .dialogue, userDefinedOriginalText: false)
        var primary = PageTranslation(imageURL: source, imageFingerprint: keys.translation,
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [effect])
        let cache = TranslationCache(cacheDirectory: root.appendingPathComponent("Cache"))
        try cache.save(primary)
        let engine = BallonsTranslatorEngine.standard(applicationSupportDirectory: root)
        let effectKey = keys.translation + "-effects-v5"
        for key in [keys.recognition, effectKey] {
            let clean = engine.inpaintedImageURL(runID: key)
            try FileManager.default.createDirectory(at: clean.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pixels.write(to: clean)
        }
        var corrected = primary; corrected.imageFingerprint = effectKey
        corrected.blocks[0].translatedText = "딸깍"; corrected.blocks[0].textKind = .soundEffect
        try cache.save(corrected)
        let directory = engine.inpaintedImageURL(runID: effectKey).deletingLastPathComponent()
        try JSONEncoder().encode(primary).write(to: directory.appendingPathComponent("effects-primary.json"))
        try JSONEncoder().encode([String]()).write(to: directory.appendingPathComponent("effects-warnings.json"))
        let processor = MangaPageProcessor(applicationSupportDirectory: root)
        for scenario in 0..<4 {
            if scenario == 1 { primary.blocks[0].effectStyleID = "impact" }
            if scenario == 2 {
                primary.blocks[0].translatedText = "직접 고친 말"
                primary.blocks[0].textKind = .dialogue; primary.blocks[0].userDefinedTextKind = true
            }
            if scenario == 3 { primary.blocks[0].keepsOriginal = true }
            try cache.save(primary)
            let result = try await processor.process(imageURL: source, destinationURL: output,
                configuration: configuration, typography: MangaTypography())
            let text = scenario >= 2 ? "직접 고친 말" : "딸깍"
            let kind: MangaTextKind = scenario >= 2 ? .dialogue : .soundEffect
            guard result.warnings.isEmpty, result.translation.blocks[0].translatedText == text,
                  result.translation.blocks[0].textKind == kind else {
                throw Failure.staleTranslation(scenario, result.translation.blocks[0], result.warnings)
            }
            guard result.translation.blocks[0].effectStyleID == primary.blocks[0].effectStyleID else { throw Failure.reviewLost }
            guard result.translation.blocks[0].keepsOriginal == primary.blocks[0].keepsOriginal else { throw Failure.reviewLost }
            if scenario == 2, result.translation.blocks[0].userDefinedTextKind != true { throw Failure.reviewLost }
            let saved = try Data(contentsOf: output)
            let repeated = try await processor.process(imageURL: source, destinationURL: output,
                configuration: configuration, typography: MangaTypography())
            guard result.translation == repeated.translation, saved == (try Data(contentsOf: output)),
                  pixels == (try Data(contentsOf: source)) else { throw Failure.changedFiles }
        }
        print("Supplemental cache passed: repaired effect survives reopen/style change, explicit review wins, repeated pixels and source preserved; no model calls")
    }

    private enum Failure: Error { case image, staleTranslation(Int, TextBlock, [String]), reviewLost, changedFiles }
}
