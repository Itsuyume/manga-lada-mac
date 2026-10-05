import Foundation
import MangaLadaCore
import MangaLadaWorkflow

enum OCRMigrationChecks {
    static func run() throws {
        let source = TextBlock(box: .init(x: 0.2, y: 0.3, width: 0.2, height: 0.3), originalText: "旧認識")
        var old = source; old.translatedText = "오래된 번역"; old.fontScale = 1.2; old.textDirection = .vertical
        var fresh = source; fresh.originalText = "新認識"
        var stored = PageTranslation(imageURL: URL(fileURLWithPath: "/fixture.png"), imageFingerprint: "ocr",
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [old])
        let marked = RecognitionCacheMigration.recordSourceEdits(in: [old], recognized: [source])
        try require(marked[0].userDefinedOriginalText == false, "Automatic old OCR was marked as a user edit")
        stored.blocks = marked
        let result = RecognitionCacheMigration.reuse(stored, for: [fresh], requiresMatchingSource: true)
        try require(result?[0].originalText == fresh.originalText && result?[0].translatedText == "", "New OCR reused a stale source/translation")
        try require(result?[0].fontScale == 1.2 && result?[0].textDirection == .vertical, "New OCR lost manual lettering")
        var reviewed = old; reviewed.originalText = "手直し"
        stored.blocks = RecognitionCacheMigration.recordSourceEdits(in: [reviewed], recognized: [source])
        try require(stored.blocks[0].userDefinedOriginalText == true, "Legacy manual correction was not identified against its original OCR")
        try require(RecognitionCacheMigration.reuse(stored, for: [fresh], requiresMatchingSource: true)?[0].originalText == reviewed.originalText,
                    "OCR upgrade replaced manual source correction")
        let retried = RecognitionCacheMigration.reuse(stored, for: [fresh], preservingOriginalOnly: true, requiresMatchingSource: true)
        try require(retried?[0].originalText == reviewed.originalText && retried?[0].translatedText.isEmpty == true,
                    "Explicit retranslation discarded the corrected source or reused old translation")
        stored.blocks[0].translatedText = ""
        let unsent = RecognitionCacheMigration.reuse(stored, for: [fresh], requiresMatchingSource: true)
        try require(unsent?[0].originalText == reviewed.originalText && unsent?[0].userDefinedOriginalText == true,
                    "OCR upgrade lost a source correction that had not yet been translated")
        var uncertain = source; uncertain.recognitionAlternatives = ["旧認識", "新認識"]
        stored.blocks = marked
        let held = RecognitionCacheMigration.reuse(stored, for: [uncertain], requiresMatchingSource: true)
        try require(held?[0].recognitionAlternatives == uncertain.recognitionAlternatives && held?[0].translatedText == "", "Stale translation bypassed OCR review")
        stored.blocks[0].keepsOriginal = true
        try require(RecognitionCacheMigration.reuse(stored, for: [fresh], preservingOriginalOnly: true, requiresMatchingSource: true)?[0].keepsOriginal == true,
                    "OCR upgrade lost original-artwork choice")
        try require(source.originalText == "旧認識" && old.translatedText == "오래된 번역", "Migration mutated input")
        try cacheKeys()
        print("OCR migration passed: stale translation rejected, original edits/lettering retained, disagreement cannot reuse cached translation")
    }

    private static func cacheKeys() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1, 2, 3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let old = try JapanesePageKeys(imageURL: url, configuration: .init(), context: "", title: "")
        let new = try JapanesePageKeys(imageURL: url, configuration: .init(japaneseOCR: .hayai), context: "", title: "")
        try require(old.translation != new.translation && old.recognition != new.recognition, "OCR backends shared stale cache keys")
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }
    private enum Failure: Error { case failed(String) }
}
