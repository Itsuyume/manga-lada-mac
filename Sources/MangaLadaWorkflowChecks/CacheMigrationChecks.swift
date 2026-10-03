import Foundation
import MangaLadaCore
import MangaLadaWorkflow

enum CacheMigrationChecks {
    static func run() throws {
        let box = TextBox(x: 0.4, y: 0.2, width: 0.1, height: 0.3)
        let saved = TextBlock(box: box, originalText: "にちっ", translatedText: "주물럭", textKind: .soundEffect,
                              effectStyleID: "soft", userDefinedBounds: box, userDefinedTextKind: true)
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
        rawOCR.userDefinedBounds = nil
        rawOCR.userDefinedTextKind = nil
        rawOCR.balloonShape = BalloonShape(bounds: box, rows: [.init(y: 0.3, left: 0.41, right: 0.49)])
        let before = rawOCR
        guard let migrated = RecognitionCacheMigration.reuse(page, for: [rawOCR])?.first else {
            throw CheckError.failed("Geometry refresh discarded corrected Japanese and retranslates the whole page.")
        }
        try require(migrated.originalText == saved.originalText && migrated.translatedText == saved.translatedText,
                    "Edited Japanese or Korean was overwritten by raw OCR.")
        try require(migrated.balloonShape == rawOCR.balloonShape && migrated.userDefinedBounds == saved.userDefinedBounds,
                    "New contours or manual placement were lost.")
        try require(migrated.textKind == saved.textKind && migrated.effectStyleID == saved.effectStyleID,
                    "Edited kind or effect style was lost.")
        try require(rawOCR == before && page.blocks == [saved], "Migration mutated its source data.")
        var empty = page
        empty.blocks[0].translatedText = ""
        try require(RecognitionCacheMigration.reuse(empty, for: [rawOCR]) == nil, "An empty translation was reused.")
        print("Cache migration checks passed: edited Japanese/Korean, new contours, manual bounds/kind/style, missing/duplicate/new/moved regions, source preserved")
    }
    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw CheckError.failed(message) }
    }
    private enum CheckError: Error { case failed(String) }
}
