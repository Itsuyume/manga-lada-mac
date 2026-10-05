import Foundation
import MangaLadaCore

enum ReadingBehaviorChecks {
    static func run() throws {
        try check(PageNavigation(count: 0, layout: .double).spread(at: 0).isEmpty, "Empty book produced a page.")
        let cover = PageNavigation(count: 6, layout: .double)
        try check(cover.spread(at: 0) == [0] && cover.spread(at: 2) == [1, 2], "Cover pairing is wrong.")
        try check(cover.displayedPages(at: 1) == [2, 1], "Japanese display order is wrong.")
        try check(cover.next(from: 3) == 5 && cover.next(from: 5) == 5, "Final odd page is not bounded.")
        try check(cover.previous(from: 5) == 3 && cover.previous(from: 0) == 0, "Previous spread skips pages.")
        let noCover = PageNavigation(count: 4, layout: .double, direction: .leftToRight, coverAlone: false)
        try check(noCover.displayedPages(at: 1) == [0, 1], "Cover-off left-to-right pairing is wrong.")
        try check(noCover.next(from: 2) == 2 && noCover.previous(from: 2) == 0, "Last full spread moves within itself.")
        let canonical = #"{"regions":[{"text":"ドーン","x":350,"y":600,"width":300,"height":100,"angle":-12}]}"#
        let effect = try OllamaSoundEffectDetector.decode(Data(canonical.utf8))[0]
        try check(effect.box.x == 0.35 && effect.rotationDegrees == -12 && effect.textKind == .soundEffect, "Effect geometry was not normalized.")
        let array = #"[{"text":"ドーン","x":350,"y":600,"width":300,"height":100,"angle":-12}]"#
        let normalized = try OllamaSoundEffectDetector.decode(Data(array.utf8))[0]
        try check(normalized.box == effect.box && normalized.originalText == effect.originalText
                  && normalized.rotationDegrees == effect.rotationDegrees, "Observed array response changed the effect geometry.")
        let runtimeVariant = #"{"regions":[{"text":"ドーン","x_min":350,"y_min":600,"width":300,"height":100}]}"#
        try check(try OllamaSoundEffectDetector.decode(Data(runtimeVariant.utf8))[0].rotationDegrees == nil, "Missing rotation was fabricated.")
        for invalid in [
            #"{"regions":[{"text":"ドーン","x":-1,"y":0,"width":3,"height":3,"angle":0}]}"#,
            #"{"regions":[{"text":"ドーン","x":999,"y":0,"width":3,"height":3,"angle":0}]}"#,
            #"{"regions":[{"text":"ドーン","x":0,"x_min":20,"y":0,"width":3,"height":3,"angle":0}]}"#,
            #"{"regions":[{"text":"","x":0,"y":0,"width":3,"height":3,"angle":0}]}"#
            , #"[{"text":"ドーン","x":999,"y":0,"width":3,"height":3}]"#
            , #"[{"text":"ドーン","x":0,"y":0}]"#
        ] {
            do { _ = try OllamaSoundEffectDetector.decode(Data(invalid.utf8)); throw ReadingCheckError.failed("Invalid geometry was accepted.") }
            catch TranslationError.invalidPageResponse { }
        }
        try checkRegionMerge()
    }
    private static func checkRegionMerge() throws {
        let optical = TextBlock(box: TextBox(x: 0.35, y: 0.6, width: 0.42, height: 0.09), originalText: "ドキドキ", translatedText: "", confidence: 0.98)
        let predicted = TextBlock(box: TextBox(x: 0.365, y: 0.712, width: 0.284, height: 0.1), originalText: "ドキドキ", translatedText: "", confidence: 0.6, textKind: .soundEffect)
        let merged = JapaneseRegionMerger.merge(existing: [], effects: [predicted], opticalCandidates: [optical])
        try check(merged.blocks.count == 1 && merged.extras.count == 1 && merged.blocks[0].box == optical.box && merged.blocks[0].textKind == .soundEffect, "Semantic/OCR reconciliation duplicated or misplaced an effect.")
        let distant = TextBlock(box: TextBox(x: 0.05, y: 0.05, width: 0.12, height: 0.1), originalText: "ドキドキ", translatedText: "", confidence: 0.98)
        let distinct = JapaneseRegionMerger.merge(existing: [], effects: [predicted], opticalCandidates: [optical, distant])
        try check(distinct.blocks.count == 2, "Repeated effects in different panels were incorrectly collapsed.")
        try check(JapaneseRegionMerger.merge(existing: [], effects: [], opticalCandidates: []).blocks.isEmpty, "Empty recognition invented text.")
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw ReadingCheckError.failed(message) } }
}
private enum ReadingCheckError: Error { case failed(String) }
