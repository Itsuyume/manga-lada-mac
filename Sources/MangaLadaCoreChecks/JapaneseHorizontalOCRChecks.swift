import Foundation
import MangaLadaCore

enum JapaneseHorizontalOCRChecks {
    static func run() throws {
        try differentDetectorHeights()
        let bounds = TextBox(x: 0.15, y: 0.16, width: 0.66, height: 0.06)
        let source = TextBlock(box: bounds, originalText: "ドアを閉めて、風でドアが勢いよく視ま", confidence: 1,
                               sourceIsVertical: false, detectedFontSize: 31.5, textKind: .caption, rotationDegrees: 0)
        let first = TextBlock(box: .init(x: 0.15, y: 0.16, width: 0.66, height: 0.033),
                              originalText: "ドアを閉めて。風でドアが勢いよく閉ま", confidence: 0.5)
        let last = TextBlock(box: .init(x: 0.44, y: 0.195, width: 0.09, height: 0.033), originalText: "った。", confidence: 0.5)
        try require(JapaneseHorizontalOCR.reconcile([], observations: [first]).isEmpty, "Empty input acquired invented regions.")
        try require(JapaneseHorizontalOCR.reconcile([source], observations: []) == [source], "Missing observations changed the page.")
        for invalid in [Float.nan, Float.infinity, 0.49] {
            var observation = first; observation.confidence = invalid
            try unchanged(source, observations: [observation], reason: "Unreliable OCR changed source text.")
        }
        for box in [TextBox(x: .nan, y: 0, width: 0.3, height: 0.04),
                    TextBox(x: 0, y: 0, width: 0, height: 0.04),
                    TextBox(x: 0.15, y: 0.8, width: 0.66, height: 0.033)] {
            var observation = first; observation.box = box
            try unchanged(source, observations: [observation], reason: "Invalid or distant OCR changed source text.")
        }
        for kind in [MangaTextKind.soundEffect, .title] {
            var protected = source; protected.textKind = kind
            try unchanged(protected, observations: [first, last], reason: "Title/effect OCR was rewritten.")
        }
        var protected = source; protected.sourceIsVertical = true
        try unchanged(protected, observations: [first, last], reason: "Vertical manga text was rewritten.")
        protected.sourceIsVertical = nil
        try unchanged(protected, observations: [first, last], reason: "Unknown writing direction was assumed horizontal.")
        protected = source; protected.translatedText = "검수한 문장"
        try unchanged(protected, observations: [first, last], reason: "Reviewed translation was changed.")
        protected = source; protected.userDefinedBounds = bounds
        try unchanged(protected, observations: [first, last], reason: "Manual source was changed.")
        protected = source; protected.userDefinedTextKind = true
        try unchanged(protected, observations: [first, last], reason: "Manual kind was changed.")
        protected = source; protected.userDefinedOriginalText = true
        try unchanged(protected, observations: [first, last], reason: "Edited source without a translation was overwritten.")
        for angle in [Double.nan, Double.infinity, 20] {
            protected = source; protected.rotationDegrees = angle
            try require(!JapaneseHorizontalOCR.canRefine(protected), "Rotated/non-finite text is eligible for horizontal OCR.")
        }
        try unchanged(source, observations: [first, first], reason: "Duplicate observations duplicated Japanese text.")
        var tiny = first; tiny.box.width = 0.03; tiny.originalText = "あ"
        try unchanged(source, observations: [tiny], reason: "Partial OCR replaced a complete sentence.")
        var nonJapanese = first; nonJapanese.originalText = "HELLO"
        try unchanged(source, observations: [nonJapanese], reason: "Non-Japanese OCR changed Japanese text.")
        var other = source; other.id = UUID()
        try require(JapaneseHorizontalOCR.reconcile([source, other], observations: [first, last]) == [source, other],
                    "Ambiguous OCR was assigned to more than one source region.")
        let before = source
        var expected = source; expected.originalText = "ドアを閉めて。風でドアが勢いよく閉まった。"
        let actual = JapaneseHorizontalOCR.reconcile([source], observations: [last, first])
        try require(actual == [expected] && source == before, "Multi-line horizontal correction failed or changed geometry/identity/style.")
        let cat = TextBlock(box: bounds, originalText: "敵が気持ちよさそうに腰を鳴らしている。", sourceIsVertical: false)
        let catObservation = TextBlock(box: bounds, originalText: "猫が気持ちよさそうに喉を鳴らしている。", confidence: 1)
        try require(JapaneseHorizontalOCR.reconcile([cat], observations: [catObservation])[0].originalText == catObservation.originalText,
                    "Matching native OCR did not correct misread horizontal kanji.")
        print("Horizontal OCR checks passed: misread kanji, complete multi-line text, coordinates/IDs preserved, vertical/manual/ambiguous/partial/invalid observations retained")
    }
    private static func differentDetectorHeights() throws {
        // Recorded from a neutral caption: native OCR includes taller line bounds than the manga detector.
        let source = TextBlock(box: .init(x: 0.1588889, y: 0.1666667, width: 0.6611111, height: 0.0225),
                               originalText: "この記事を書くことは、わかりますので、", confidence: 1,
                               sourceIsVertical: false, detectedFontSize: 27, rotationDegrees: 0)
        let observation = TextBlock(box: .init(x: 0.1444444, y: 0.1666667, width: 0.6944444, height: 0.0416667),
                                    originalText: "川の浅瀬を歩くたびに、水が足元で跳ねる。", confidence: 0.5)
        var expected = source; expected.originalText = observation.originalText
        try require(JapaneseHorizontalOCR.reconcile([source], observations: [observation]) == [expected],
                    "Complete native line was rejected because the manga detector used shorter bounds.")
        let unchangedSource = source
        for factor in [2.01, 3.0] {
            var oversized = observation
            oversized.box.height = source.box.height * factor
            oversized.box.y = source.box.y + (source.box.height - oversized.box.height) / 2
            try unchanged(source, observations: [oversized], reason: "Tall unrelated text replaced a narrow line.")
        }
        var wide = observation; wide.box.width = source.box.width * 1.26
        wide.box.x = source.box.x + (source.box.width - wide.box.width) / 2
        try unchanged(source, observations: [wide], reason: "Overwide native text replaced a narrow line.")
        var shifted = observation; shifted.box.y += source.box.height
        try unchanged(source, observations: [shifted], reason: "Adjacent native line was assigned to the wrong source.")
        var partial = observation; partial.box.width = source.box.width * 0.5
        try unchanged(source, observations: [partial], reason: "Partial native reading replaced a complete line.")
        var overlapping = source; overlapping.id = UUID(); overlapping.box.y += 0.005
        try require(JapaneseHorizontalOCR.reconcile([source, overlapping], observations: [observation]) == [source, overlapping],
                    "Expanded native bounds were assigned to ambiguous overlapping lines.")
        try unchanged(source, observations: [observation, observation], reason: "Duplicate tall readings were combined.")
        try require(source == unchangedSource, "Reconciliation mutated the original block.")
    }
    private static func unchanged(_ block: TextBlock, observations: [TextBlock], reason: String) throws {
        try require(JapaneseHorizontalOCR.reconcile([block], observations: observations) == [block], reason)
    }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckError.failed(message) }
    }
    private enum CheckError: Error { case failed(String) }
}
