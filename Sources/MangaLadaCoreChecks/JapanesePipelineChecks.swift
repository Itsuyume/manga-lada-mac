import Foundation
import MangaLadaCore

enum JapanesePipelineChecks {
    static func run() throws {
        let blocks = [
            TextBlock(box: TextBox(x: 0.7, y: 0.1, width: 0.2, height: 0.2), originalText: "急いで！"),
            TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.3, height: 0.2), originalText: "ドーン")
        ]
        let valid = #"{"translations":[{"id":1,"text":"쾅","kind":"soundEffect"},{"id":0,"text":"서둘러!","kind":"dialogue"}]}"#
        let result = try MangaPageResponse.decode(Data(valid.utf8), blocks: blocks)
        try check(result.map(\.translatedText) == ["서둘러!", "쾅"], "Page response lost region identity.")
        try check(result[1].textKind == .soundEffect, "SFX classification was lost.")
        try check(result[0].box == blocks[0].box, "Translation changed the source geometry.")
        for invalid in [
            #"{"translations":[]}"#,
            #"{"translations":[{"id":0,"text":"안녕","kind":"dialogue"},{"id":0,"text":"쾅","kind":"soundEffect"}]}"#,
            #"{"translations":[{"id":0,"text":" ","kind":"dialogue"},{"id":1,"text":"쾅","kind":"soundEffect"}]}"#,
            #"{"translations":[{"id":0,"text":"急いで","kind":"dialogue"},{"id":1,"text":"쾅","kind":"soundEffect"}]}"#,
            #"{"translations":[{"id":0,"text":"그弁当, 혼자 다 못 먹어","kind":"dialogue"},{"id":1,"text":"쾅","kind":"soundEffect"}]}"#
        ] {
            do {
                _ = try MangaPageResponse.decode(Data(invalid.utf8), blocks: blocks)
                throw JapaneseCheckError.failed("Malformed page output was accepted.")
            } catch TranslationError.invalidPageResponse { }
        }
        try check(try MangaPageResponse.decode(Data(#"{"translations":[]}"#.utf8), blocks: []).isEmpty, "Empty page failed.")
        let interruption = [TextBlock(box: blocks[0].box, originalText: "．．．っ！")]
        try check(try MangaNumberedPageResponse.decode("[R0] ...!", blocks: interruption)[0].translatedText == "...!", "Standalone breath/interruption punctuation was rejected as untranslated dialogue.")
        let local = LocalTranslatorConfiguration()
        try check(local.provider == .ollama, "Default translator sends data to the cloud.")
        try check(!local.usesPreviousPageContext && LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: "qwen3.5:9b")).usesPreviousPageContext,
                  "Cache context does not follow the model's actual translation contract.")
        try check(local.ollama.model == "translategemma:12b" && !local.enhanceSoundEffects, "Default mode uses an expensive optional image-analysis stage.")
        let numbered = try MangaNumberedPageResponse.decode("[R1] 쾅\n[R0] 서둘러!", blocks: blocks)
        try check(numbered.map(\.translatedText) == ["서둘러!", "쾅"], "Numbered translation changed reading-region identity.")
        do { _ = try MangaNumberedPageResponse.decode("[R0] 서둘러!", blocks: blocks); throw JapaneseCheckError.failed("Missing numbered translation was accepted.") }
        catch TranslationError.invalidPageResponse { }
        try check(JapaneseTitleResolver.resolve(optical: "青い剣士と赤い術師", bookTitle: "青い剣士と赤い術士") == "青い剣士と赤い術士", "Decorative title OCR did not use near-matching archive metadata.")
        try check(JapaneseTitleResolver.resolve(optical: "ぜんぜん違う文章ですよ", bookTitle: "青い剣士と赤い術士") == "ぜんぜん違う文章ですよ", "Unrelated dialogue was replaced by a book title.")
        let partial = JapaneseRegionMerger.merge(existing: [blocks[0]], effects: [TextBlock(box: blocks[0].box, originalText: "急", textKind: .soundEffect)], opticalCandidates: [])
        try check(partial.blocks[0].textKind == blocks[0].textKind, "One overlapping sound-effect fragment reclassified a whole dialogue.")
        let misplaced = TextBlock(box: TextBox(x: 0.55, y: 0.05, width: 0.15, height: 0.06), originalText: "急いで", textKind: .soundEffect)
        let rejected = JapaneseRegionMerger.merge(existing: blocks, effects: [misplaced], opticalCandidates: [])
        try check(rejected.extras.isEmpty && rejected.unverified == 1, "An ungrounded vision guess erased artwork or duplicated speech.")
        let optical = TextBlock(box: TextBox(x: 0.05, y: 0.7, width: 0.1, height: 0.07), originalText: "バン", confidence: 0.9)
        let candidate = TextBlock(box: optical.box, originalText: "バン", textKind: .soundEffect)
        let grounded = JapaneseRegionMerger.merge(existing: blocks, effects: [candidate], opticalCandidates: [optical])
        try check(grounded.extras.count == 1 && grounded.extras[0].textKind == .soundEffect && grounded.unverified == 0,
                  "Independently located sound-effect text was lost or duplicated.")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let container = BalloonShape(bounds: TextBox(x: 0.1, y: 0.1, width: 0.5, height: 0.3), rows: [])
        let left = TextBlock(box: TextBox(x: 0.2, y: 0.1, width: 0.1, height: 0.2), originalText: "左の台詞", balloonShape: container)
        let right = TextBlock(box: TextBox(x: 0.4, y: 0.1, width: 0.1, height: 0.2), originalText: "右の台詞", balloonShape: container)
        let grouped = JapaneseRegionMerger.speechRegions([left, right])
        try check(grouped.count == 1 && grouped[0].originalText == "右の台詞 左の台詞", "One balloon's split OCR columns were not combined in Japanese reading order.")
        let duplicate = TextBlock(box: TextBox(x: 0.4, y: 0.1, width: 0.05, height: 0.1), originalText: "右の")
        try check(JapaneseRegionMerger.speechRegions([right, duplicate]).count == 1, "Contained OCR text was translated twice.")
        try check(JapaneseRegionMerger.speechRegions([]).isEmpty, "Empty OCR regions changed behavior.")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        let cloud = LocalTranslatorConfiguration(provider: .geminiFlashLite, gemini: GeminiConfiguration(apiKey: "test-secret-do-not-save"))
        try cloud.save(to: url)
        let serialized = try String(contentsOf: url, encoding: .utf8)
        try check(!serialized.contains("test-secret"), "API key leaked into settings JSON.")
        let restored = try LocalTranslatorConfiguration.load(configURL: url, environment: [:])
        try check(restored.gemini.apiKey.isEmpty && restored.provider == .geminiFlashLite, "Settings did not preserve provider without the key.")
        try check(local.cacheKey != cloud.cacheKey, "Provider changes reuse the wrong translation cache.")
        try check(MangaReadingOrder.sorted(blocks).first?.id == blocks[0].id, "Japanese reading order must start at the right.")
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw JapaneseCheckError.failed(message) }
    }
}

private enum JapaneseCheckError: Error {
    case failed(String)
}
