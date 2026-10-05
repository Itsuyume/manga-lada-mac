import Foundation
import MangaLadaCore
import MangaLadaWorkflow

enum CacheMigrationChecks {
    static func run() throws {
        try OCRMigrationChecks.run()
        let box = TextBox(x: 0.4, y: 0.2, width: 0.1, height: 0.3)
        let saved = TextBlock(box: box, originalText: "にちっ", translatedText: "주물럭", textKind: .soundEffect,
                              effectStyleID: "soft", textDirection: .vertical, fontScale: 0.8, textOffset: .init(x: 0.01, y: 0.02),
                              textLayoutBounds: box, userDefinedBounds: box, userDefinedTextKind: true)
        let page = PageTranslation(imageURL: URL(fileURLWithPath: "/fixture.png"), imageFingerprint: "fixture",
                                   sourceLanguage: .japanese, targetLanguage: .korean, blocks: [saved])
        try require(RecognitionCacheMigration.reuse(page, for: []) == nil, "Missing regions reused an unrelated translation.")
        try require(RecognitionCacheMigration.reuse(page, for: [saved, saved]) == nil, "Duplicate regions were accepted.")
        var changed = saved
        changed.id = UUID()
        try require(RecognitionCacheMigration.reuse(page, for: [changed]) == nil, "Fresh OCR inherited a stale translation.")
        changed = saved
        changed.box.x += 0.1
        try require(RecognitionCacheMigration.reuse(page, for: [changed]) == nil, "A moved source region inherited a stale translation.")
        var rawOCR = saved
        rawOCR.originalText = "にゃっ"
        rawOCR.translatedText = ""
        rawOCR.textKind = .dialogue
        rawOCR.effectStyleID = nil
        rawOCR.textDirection = nil; rawOCR.fontScale = nil; rawOCR.textOffset = nil
        rawOCR.textLayoutBounds = nil
        rawOCR.userDefinedBounds = nil
        rawOCR.userDefinedTextKind = nil
        rawOCR.balloonShape = BalloonShape(bounds: box, rows: [.init(y: 0.3, left: 0.41, right: 0.49)])
        let before = rawOCR
        guard let migrated = RecognitionCacheMigration.reuse(page, for: [rawOCR])?.first else {
            throw CheckError.failed("Geometry refresh discarded corrected Japanese and retranslates the whole page.")
        }
        try require(migrated.originalText == saved.originalText && migrated.translatedText == saved.translatedText,
                    "Edited Japanese or Korean was overwritten by raw OCR.")
        try require(migrated.userDefinedOriginalText == true, "Legacy corrected source text lost its preservation marker.")
        try require(migrated.balloonShape == rawOCR.balloonShape && migrated.userDefinedBounds == saved.userDefinedBounds,
                    "New contours or manual placement were lost.")
        try require(migrated.textKind == saved.textKind && migrated.effectStyleID == saved.effectStyleID,
                    "Edited kind or effect style was lost.")
        try require(migrated.textDirection == saved.textDirection && migrated.fontScale == saved.fontScale && migrated.textOffset == saved.textOffset,
                    "Geometry refresh lost manual lettering controls.")
        try require(migrated.textLayoutBounds == saved.textLayoutBounds, "Geometry refresh lost typesetting space.")
        try require(rawOCR == before && page.blocks == [saved], "Migration mutated its source data.")
        var interpreted = page
        interpreted.blocks[0].maskedTextInterpretation = MaskedTextInterpretation(japanese: "推定した日本語", message: "뜻 확인")
        try require(RecognitionCacheMigration.reuse(interpreted, for: [rawOCR])?.first?.maskedTextInterpretation
                    == interpreted.blocks[0].maskedTextInterpretation, "Geometry refresh lost interpretation review information.")
        var automatic = page
        automatic.blocks[0].userDefinedTextKind = nil
        automatic.blocks[0].textKind = .dialogue
        rawOCR.textKind = .caption
        let reclassified = RecognitionCacheMigration.reuse(automatic, for: [rawOCR])?.first
        try require(reclassified?.textKind == .caption && reclassified?.translatedText == saved.translatedText,
                    "A new detected caption was lost or retranslated while migrating an automatic dialogue kind.")
        rawOCR.textKind = .soundEffect
        try require(RecognitionCacheMigration.reuse(automatic, for: [rawOCR])?.first?.textKind == .soundEffect,
                    "An old automatic dialogue kind suppressed an updated sound-effect hint.")
        var empty = page
        empty.blocks[0].translatedText = ""
        try require(RecognitionCacheMigration.reuse(empty, for: [rawOCR]) == nil, "An empty translation was reused.")
        let extra = TextBlock(box: .init(x: 0.1, y: 0.7, width: 0.3, height: 0.08), originalText: "カチッ", textKind: .soundEffect)
        guard let augmented = RecognitionCacheMigration.reuse(page, for: [rawOCR, extra]) else {
            throw CheckError.failed("A newly detected effect discarded previously reviewed Japanese and Korean.")
        }
        try require(augmented[0].originalText == saved.originalText && augmented[0].translatedText == saved.translatedText,
                    "Adding an effect lost reviewed text.")
        try require(augmented[0].userDefinedTextKind == true && augmented[0].effectStyleID == saved.effectStyleID
                    && augmented[1] == extra, "Adding an effect lost manual style or pre-translated the new region.")
        var moved = rawOCR; moved.box.x += 0.1
        try require(RecognitionCacheMigration.reuse(page, for: [moved, extra]) == nil, "Moved source reused reviewed text while adding an effect.")
        var manualPunctuation = saved
        manualPunctuation.originalText = "．．．"; manualPunctuation.translatedText = "．．．"
        manualPunctuation.effectStyleID = nil; manualPunctuation.userDefinedOriginalText = false
        manualPunctuation.verifiedPunctuationBounds = box
        var manualPage = page; manualPage.blocks = [manualPunctuation]
        var earlierOCR = rawOCR; earlierOCR.originalText = "・"
        let restoredManual = RecognitionCacheMigration.reuse(manualPage, for: [earlierOCR])!
        try require(restoredManual[0].verifiedPunctuationBounds == box && restoredManual[0].userDefinedOriginalText == false,
                    "An older partial OCR changed verified manual punctuation into a user edit.")
        try require(try JSONDecoder().decode(PageTranslation.self, from: JSONEncoder().encode(manualPage)) == manualPage,
                    "Manual source bounds were lost during cache encoding.")
        var compound = saved; compound.id = UUID(); compound.box.x = 0.05
        var mixed = page; mixed.blocks = [saved, compound]
        var lobe = compound; lobe.id = UUID(); lobe.box.width /= 2; lobe.translatedText = ""
        guard let separated = RecognitionCacheMigration.reuse(mixed, for: [rawOCR, lobe]) else {
            throw CheckError.failed("Splitting a different balloon discarded an unchanged reviewed region.")
        }
        try require(separated[0].translatedText == saved.translatedText && separated[0].effectStyleID == saved.effectStyleID
                    && separated[1].translatedText.isEmpty, "A new lobe reused its old combined sentence or lost a neighboring review.")
        var keptPage = page; keptPage.blocks[0].keepsOriginal = true; keptPage.blocks[0].translatedText = ""
        let kept = RecognitionCacheMigration.reuse(keptPage, for: [rawOCR, extra], preservingOriginalOnly: true)
        try require(kept?.first?.keepsOriginal == true && kept?.first?.translatedText == "" && kept?.last == extra,
                    "Forced recognition refresh lost explicit original-only choice or changed its neighbor.")
        try require(RecognitionCacheMigration.reuse(page, for: [rawOCR], preservingOriginalOnly: true) == nil,
                    "Forced refresh reused a non-excluded translation.")
        print("Cache migration checks passed: edited Japanese/Korean, new contours, manual bounds/kind/style, missing/duplicate/new/moved regions, source preserved")
    }
    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw CheckError.failed(message) }
    }
    private enum CheckError: Error { case failed(String) }
}
