import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkOCRReview(session: URLSession) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let pending = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.4), originalText: "パチパチ",
            recognitionAlternatives: ["パチパチ", "パチパチパチ", "ポチ"], textKind: .soundEffect)
        let active = TextBlock(box: .init(x: 0.5, y: 0.1, width: 0.2, height: 0.2), originalText: "ありがとう")
        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Uncertain OCR reached a translation model") }
        let configuration = LocalTranslatorConfiguration(japaneseOCR: .hayai)
        try check(pending.keepsOriginal == nil && pending.preservesOriginalArtwork, "OCR hold was confused with a user deletion")
        try check(try await pipeline.translate([pending], configuration: configuration) == [pending], "Uncertain OCR was changed")
        try check(try await pipeline.translateSelected([pending.id], in: [pending, active], configuration: configuration) == [pending, active],
                  "Uncertain selection affected another region")
        try check(FixtureProtocol.state.count == 0, "Uncertain OCR had a network side effect")
        let page = PageTranslation(imageURL: URL(fileURLWithPath: "/fixture.png"), imageFingerprint: "ocr-review",
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [pending, active])
        try check(page.untranslatedBlockIDs == [active.id], "OCR hold blocked unrelated translation")
        try check(try JSONDecoder().decode(PageTranslation.self, from: JSONEncoder().encode(page)) == page, "OCR alternatives did not persist")
        var corrected = pending; corrected.originalText = "パチパチパチパチ"
        try check(corrected.recognitionAlternatives == nil && !corrected.preservesOriginalArtwork, "Source correction did not release review hold")
        var deleted = pending; deleted.keepsOriginal = true; deleted.originalText = "パチ"
        try check(deleted.preservesOriginalArtwork, "OCR correction undid explicit original choice")
        var blank = pending; blank.originalText = ""; blank.recognitionAlternatives = []
        try check(blank.preservesOriginalArtwork, "No readable candidate was accepted as a blank result")
        try check(JapaneseSpeechGrouping.resolve([blank, pending]).count == 2, "OCR grouping discarded an uncertain region")
        try check(!JapaneseHorizontalOCR.canRefine(pending), "Another recognizer silently resolved an OCR disagreement")
        try check(pending.applyingReviewChanges(from: pending, to: corrected).recognitionAlternatives == nil,
                  "Saved review restored the obsolete OCR hold")
        var confirmed = pending; confirmed.recognitionAlternatives = nil; confirmed.userDefinedOriginalText = true
        try check(pending.applyingReviewChanges(from: pending, to: confirmed) == confirmed,
                  "Confirming an unchanged OCR candidate lost its manual-source provenance")
        try checkOCRConfiguration(configuration)
        print("OCR review checks passed: no translation calls, persistence, correction, original choice, grouping and configuration")
    }

    private static func checkOCRConfiguration(_ configuration: LocalTranslatorConfiguration) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        try configuration.save(to: url)
        let loaded = try LocalTranslatorConfiguration.load(configURL: url, environment: [:])
        try check(loaded.japaneseOCR == .hayai, "Selected OCR backend was not saved")
        var detected = configuration; detected.japaneseOCR = .hayaiDetected
        try detected.save(to: url)
        try check(try LocalTranslatorConfiguration.load(configURL: url, environment: [:]).japaneseOCR == .hayaiDetected,
                  "Detector-assisted OCR selection was not saved")
        try check(detected.japaneseOCR.usesLetteringOCR && !JapaneseOCRBackend.manga.usesLetteringOCR,
                  "The detector option changed recognizers implicitly")
        try check(!detected.requiresRetranslation(comparedTo: configuration), "Detector selection discarded existing reviews")
        var precise = configuration; precise.japaneseOCR = .hayaiTextStrokes
        try precise.save(to: url)
        try check(try LocalTranslatorConfiguration.load(configURL: url, environment: [:]).japaneseOCR == .hayaiTextStrokes,
                  "Precise stroke OCR selection was not saved")
        try check(precise.japaneseOCR.usesLetteringOCR && !precise.requiresRetranslation(comparedTo: detected),
                  "Precise stroke selection discarded existing reviews")
        var changed = configuration; changed.japaneseOCR = .manga
        try check(!changed.requiresRetranslation(comparedTo: configuration), "OCR selection discarded saved reviews")
        try Data("{}".utf8).write(to: url)
        try check(try LocalTranslatorConfiguration.load(configURL: url, environment: [:]).japaneseOCR == .manga,
                  "Legacy configuration changed OCR without selection")
        try Data(#"{"japaneseOCR":"unknown"}"#.utf8).write(to: url)
        do {
            _ = try LocalTranslatorConfiguration.load(configURL: url, environment: [:])
            throw BoundaryCheckError.failed("Invalid OCR configuration silently selected a backend")
        } catch is DecodingError { }
    }
}
