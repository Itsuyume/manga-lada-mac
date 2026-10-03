import Foundation
import MangaLadaCore

enum SoundEffectTranslationChecks {
    static func run() throws {
        for invalid in ["", "  ", "カチッ", "그弁当"] {
            do {
                _ = try decode(source: "カチッ", text: invalid)
                throw CheckError.failed("An effect dictionary hid an invalid or untranslated model response.")
            } catch TranslationError.invalidPageResponse { }
        }
        for kind in [MangaTextKind.dialogue, .caption, .title] {
            let text = "(전등 스위치 소리) \"딸깍\""
            try check(try decode(source: "カチッ", text: text, kind: kind).translatedText == text,
                      "Non-effect text was rewritten by effect formatting.")
        }
        let examples = [
            ("カチッ", "(전등 스위치 소리) \"딸깍\"", "딸깍"),
            ("ｶﾁｯ", "카칫", "딸깍"),
            ("ザアア…", "(바람 소리) 자아아...", "쏴아아"),
            ("バタン", "박당", "쾅"),
            ("ドキドキ", "도키도키", "두근두근"),
            ("パリン", "파링", "쨍그랑"),
            ("ポチャン", "포창", "퐁당"),
            ("ガタガタ", "(기계 소리) “덜덜”", "덜덜"),
            ("ゴロゴロ", "우르릉", "우르릉"),
            ("ゴロゴロ", "골골", "골골"),
            ("ゴロゴロ", "(멀리서) 우르릉", "(멀리서) 우르릉"),
            ("ゴロゴロ", "우르릉 (천둥 소리)", "우르릉 (천둥 소리)")
        ]
        for (source, text, expected) in examples {
            let result = try decode(source: source, text: text)
            try check(result.translatedText == expected, "Unexpected effect output for \(source): \(result.translatedText)")
        }
        for annotation in ["(기계 소리)", "(효과음) \"\"", "(기계 소리) click"] {
            do {
                _ = try decode(source: "ガタガタ", text: annotation)
                throw CheckError.failed("Annotation-only sound effect was accepted.")
            } catch TranslationError.invalidPageResponse { }
        }
        try checkLexicon()
        print("Sound-effect translation checks passed: concise Korean forms, context-dependent variants retained, commentary formatting, non-effects untouched, malformed output rejected")
    }

    private static func checkLexicon() throws {
        for invalid in ["null", #"{"version":2,"entries":[]}"#, #"{"version":1,"entries":[]}"#,
                        #"{"version":1,"entries":[{"sources":[""]}]}"#,
                        #"{"version":1,"entries":[{"sources":["カチッ"]}],"recognitionPatterns":["["]}"#,
                        #"{"version":1,"entries":[{"sources":["カチッ"]}],"recognitionPatterns":[""]}"#,
                        #"{"version":1,"entries":[{"sources":["カチッ"],"korean":"click"}]}"#,
                        #"{"version":1,"entries":[{"sources":["カチッ","ｶﾁｯ"]}]}"#] {
            var rejected = false
            do { _ = try JapaneseSoundEffectLexicon(data: Data(invalid.utf8)) }
            catch { rejected = true }
            try check(rejected, "Invalid or duplicate effect catalog was accepted.")
        }
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        try check(lexicon.sourceForms.contains("ゴロゴロ") && lexicon.translation(for: "ゴロゴロ") == nil,
                  "A context-dependent effect was assigned one fixed meaning.")
        try check(lexicon.translation(for: "カチッと音がした") == nil && lexicon.translation(for: "") == nil,
                  "A partial word or empty source matched an effect entry.")
        try check(lexicon.sourceForms.count == Set(lexicon.sourceForms).count, "OCR hints contain duplicate source forms.")
    }

    private static func decode(source: String, text: String, kind: MangaTextKind = .soundEffect) throws -> TextBlock {
        let bounds = TextBox(x: 0.1, y: 0.2, width: 0.2, height: 0.1)
        let block = TextBlock(box: bounds, originalText: source, textKind: kind, rotationDegrees: -15,
                              effectStyleID: "impact", userDefinedBounds: bounds, userDefinedTextKind: true)
        let before = block
        let payload = Response(translations: [.init(id: 0, text: text, kind: "soundEffect")])
        let result = try MangaPageResponse.decode(JSONEncoder().encode(payload), blocks: [block])[0]
        try check(result.id == block.id && result.box == block.box && result.originalText == block.originalText && result.textKind == kind,
                  "Effect translation changed identity, source, geometry, or an explicit kind.")
        try check(result.userDefinedBounds == bounds && result.rotationDegrees == -15 && result.effectStyleID == "impact" && block == before,
                  "Effect translation changed manual placement, style, rotation, or the input block.")
        return result
    }
    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckError.failed(message) }
    }
    private struct Response: Encodable { let translations: [Entry] }
    private struct Entry: Encodable { let id: Int; let text: String; let kind: String }
    private enum CheckError: Error { case failed(String) }
}
