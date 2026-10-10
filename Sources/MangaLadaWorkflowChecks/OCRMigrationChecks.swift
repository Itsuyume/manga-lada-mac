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
        let detected = try JapanesePageKeys(imageURL: url, configuration: .init(japaneseOCR: .hayaiDetected), context: "", title: "")
        let precise = try JapanesePageKeys(imageURL: url, configuration: .init(japaneseOCR: .hayaiTextStrokes), context: "", title: "")
        try require(precise.translation != detected.translation && precise.recognition != detected.recognition,
                    "Precise stroke OCR reused an obsolete erasure mask")
        try require(precise.previousRecognition.contains(detected.recognition) && precise.previous.contains(detected.translation),
                    "Precise stroke upgrade cannot preserve previous manual review edits")
        try require(detected.translation != new.translation && detected.recognition != new.recognition,
                    "Detector-assisted OCR reused a cache without the newly recovered regions")
        try require(detected.previousRecognition.contains(new.recognition) && detected.previous.contains(new.translation),
                    "Detector upgrade cannot preserve existing Hayai review edits")
        try require(old.translation != new.translation && old.recognition != new.recognition, "OCR backends shared stale cache keys")
        try require(new.previousRecognition.first == new.recognitionBeforeCleanupUpdate + "-ink-v4"
                    && new.previousRecognition.contains(new.recognitionBeforeCleanupUpdate),
                    "Cleanup refresh cannot reuse the matching OCR policy")
        try require(new.previousRecognition.contains(old.recognitionBeforeCleanupUpdate + "-hayai-v1"),
                    "Previous Hayai OCR is unavailable for preserving manual source edits")
        try require(new.previous.contains(old.translation + "-hayai-v1"),
                    "Previous Hayai review is unavailable for migration")
        for (keys, suffix) in [(new, "-hayai-v2"), (detected, "-hayai-detected-v1"),
                              (detected, "-hayai-detected-v2"), (detected, "-hayai-detected-v3"),
                              (detected, "-hayai-detected-v4"),
                              (precise, "-hayai-text-strokes-v1"), (precise, "-hayai-text-strokes-v2")] {
            let priorRecognition = old.recognitionBeforeCleanupUpdate + suffix + "-ink-v2"
            let priorTranslation = old.translation + suffix
            try require(keys.recognition != priorRecognition && keys.translation != priorTranslation,
                        "Source-disagreement policy reused an old automatic acceptance")
            try require(keys.previousRecognition.contains(priorRecognition) && keys.previous.contains(priorTranslation),
                        "Source-disagreement policy lost previous manual reviews")
        }
        for keys in [old, new, detected, precise] {
            try require(keys.reusableRecognition.contains(keys.recognitionBeforeCleanupUpdate + "-ink-v4")
                        && keys.reusableRecognition.contains(keys.recognitionBeforeCleanupUpdate + "-ink-v3")
                        && keys.reusableRecognition.contains(keys.recognitionBeforeCleanupUpdate + "-ink-v2")
                        && keys.reusableRecognition.contains(keys.recognitionBeforeCleanupUpdate),
                        "Cleanup-only refresh cannot reuse the current OCR policy")
            try require(keys.recognition != keys.recognitionBeforeCleanupUpdate
                        && keys.previousRecognition.first == keys.recognitionBeforeCleanupUpdate + "-ink-v4"
                        && keys.previousRecognition.contains(keys.recognitionBeforeCleanupUpdate),
                        "Unsafe old cleanup image can bypass regeneration")
            try require(keys.previous.first != keys.translation && Set(keys.previous).count == keys.previous.count,
                        "Cleanup update duplicated or reused current translation keys")
        }
        try require(!new.previousRecognition.contains(new.recognition) && !new.previous.contains(new.translation),
                    "Current OCR accidentally reuses a prior policy key")
        try require(!precise.reusableRecognition.contains(detected.recognition)
                    && !detected.reusableRecognition.contains(new.recognition),
                    "Different OCR policies were allowed to skip fresh recognition")
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }
    private enum Failure: Error { case failed(String) }
}
