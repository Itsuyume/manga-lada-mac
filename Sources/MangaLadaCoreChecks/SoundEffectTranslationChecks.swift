import Foundation
import MangaLadaCore

enum SoundEffectTranslationChecks {
    static func run() throws {
        try checkReviewOptions()
        try checkPunctuationEffects()
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
            ("ザアァーッ", "자아-!", "쏴아아"),
            ("バタン", "박당", "쾅"),
            ("ドキドキ", "도키도키", "두근두근"),
            ("パリン", "파링", "쨍그랑"),
            ("ポチャン", "포창", "퐁당"),
            ("シーン", "장면.", "정적…"),
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
        try checkKindRefinement()
        print("Sound-effect translation checks passed: concise Korean forms, context-dependent variants retained, commentary formatting, non-effects untouched, malformed output rejected")
    }

    private static func checkReviewOptions() throws {
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        for source in ["", "カチッと音がした", "にちっと音がした", "未知の言葉"] {
            try check(lexicon.reviewOptions(for: source).isEmpty, "An unknown or embedded phrase received isolated effect choices.")
        }
        let options = lexicon.reviewOptions(for: "ゴロゴロ")
        try check(options.contains { $0.context == "천둥" && $0.korean == "우르릉" }, "Thunder review choice is missing.")
        try check(options.contains { $0.context == "고양이" && $0.korean == "가르랑" }, "Cat review choice is missing.")
        try check(lexicon.reviewOptions(for: "ｺﾞﾛｺﾞﾛ。") == options && lexicon.reviewOptions(for: "ごろごろ") == options,
                  "Script or width variants lost the same review choices.")
        try check(lexicon.translation(for: "ゴロゴロ") == nil, "Review choices became an automatic fixed translation.")
        let minimal = #"{"version":1,"entries":[{"sources":["ゴロゴロ"]}]}"#
        try check(try JapaneseSoundEffectLexicon(data: Data(minimal.utf8)).reviewOptions(for: "ゴロゴロ").isEmpty,
                  "An older catalog without review choices was rejected.")
        let goodOptions = #"[{"context":"천둥","korean":"우르릉"},{"context":"고양이","korean":"가르랑"}]"#
        let invalidGroups = [
            #"[{"sources":[],"options":OPTIONS}]"#,
            #"[{"sources":["ニチッ"],"options":OPTIONS}]"#,
            #"[{"sources":["ゴロゴロ","ｺﾞﾛｺﾞﾛ"],"options":OPTIONS}]"#,
            #"[{"sources":["ゴロゴロ"],"options":[]}]"#,
            #"[{"sources":["ゴロゴロ"],"options":[{"context":"천둥","korean":"우르릉"}]}]"#,
            #"[{"sources":["ゴロゴロ"],"options":[{"context":"천둥","korean":"우르릉"},{"context":"천둥","korean":"우르릉"}]}]"#,
            #"[{"sources":["ゴロゴロ"],"options":[{"context":"","korean":"우르릉"},{"context":"고양이","korean":"가르랑"}]}]"#,
            #"[{"sources":["ゴロゴロ"],"options":[{"context":"천둥","korean":"ゴロ"},{"context":"고양이","korean":"가르랑"}]}]"#,
            #"[{"sources":["ゴロゴロ"],"options":OPTIONS},{"sources":["ゴロゴロ"],"options":OPTIONS}]"#
        ]
        for group in invalidGroups {
            let data = Data((#"{"version":1,"entries":[{"sources":["ゴロゴロ"]}],"reviewGroups":GROUPS}"#
                .replacingOccurrences(of: "GROUPS", with: group).replacingOccurrences(of: "OPTIONS", with: goodOptions)).utf8)
            var rejected = false
            do { _ = try JapaneseSoundEffectLexicon(data: data) } catch { rejected = true }
            try check(rejected, "Invalid, duplicate, or unregistered effect choices were accepted.")
        }
    }

    private static func checkPunctuationEffects() throws {
        for (source, text) in [("…", "..."), ("!?", "!?"), ("……", "……"), ("！？", "!?"),
                               ("．．．っ！", "...!"), ("｢!?｣", "!?"), ("ッ", "!"), ("｢…｣", "…"), ("・・・", "…"), ("ー", "—")] {
            for kind in MangaTextKind.allCases {
                try check(try decode(source: source, text: text, kind: kind).translatedText == text,
                          "Expressive punctuation failed for \(kind): \(source).")
            }
        }
        for (source, text) in [("", "..."), (" ", "..."), ("「」", "..."), ("123", "..."), ("click", "..."),
                               ("カチッ", "..."), ("急いで！", "!"), ("っ12", "!"), ("っa", "!"),
                               ("…", ""), ("…", " "), ("…", "「」"), ("…", "(효과음)"), ("…", "click"), ("…", "ッ"), ("…", "12")] {
            do {
                _ = try decode(source: source, text: text)
                throw CheckError.failed("Punctuation exception accepted an empty, untranslated or unrelated effect: \(source) / \(text)")
            } catch TranslationError.invalidPageResponse { }
        }
        let context = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.4, height: 0.2), originalText: "静かになった。", translatedText: "검수한 문구", textKind: .caption)
        let effect = TextBlock(box: TextBox(x: 0.6, y: 0.6, width: 0.2, height: 0.1), originalText: "…", textKind: .soundEffect)
        let payload = Response(translations: [.init(id: 0, text: "静かになった。", kind: "caption"), .init(id: 1, text: "...", kind: "soundEffect")])
        let result = try MangaPageResponse.decode(JSONEncoder().encode(payload), blocks: [context, effect], selectedIDs: [effect.id])
        try check(result[0] == context && result[1].translatedText == "...", "Punctuation selection changed unrelated reviewed text.")
    }

    private static func checkKindRefinement() throws {
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        try check(lexicon.inferKinds([]).isEmpty, "Empty OCR produced an effect.")
        for source in ["カチッ", "ｶﾁｯ。", "バタンバタン", "ザアァーッ", "ゴロゴロ", "にちっ", "ニチッ", "ﾆﾁｯ", "にちゃっ", "にちゃにちゃ", "ニチャニチャ"] {
            try check(lexicon.recognizes(source), "A catalog form or complete effect pattern was missed: \(source)")
        }
        for source in ["", "ナナ", "あっ", "ああ", "ふふふ", "あっさり", "カチッと音がした", "大きなバタン", "バタンと", "にちっと音がした", "こんにちは", "にゃっ", "ニチカ", "きっと", "バビュンと走った", "バビュ"] {
            try check(!lexicon.recognizes(source), "Dialogue, a name, or a partial match became an effect: \(source)")
        }
        let bounds = TextBox(x: 0.2, y: 0.6, width: 0.5, height: 0.08)
        let block = TextBlock(box: bounds, originalText: "バタンパタン", sourceIsVertical: false, textKind: .dialogue)
        let observed = TextBlock(box: bounds, originalText: "バタンバタン", confidence: 1)
        let corrected = JapaneseHorizontalOCR.reconcile([block], observations: [observed])
        let effect = lexicon.inferKinds(corrected)[0]
        try check(effect.originalText == "バタンバタン" && effect.textKind == .soundEffect,
                  "Correcting OCR left a recognized effect styled as dialogue.")
        var expected = corrected[0]; expected.textKind = .soundEffect
        try check(effect == expected && effect.id == block.id && effect.box == block.box,
                  "Kind refinement changed source identity, geometry, or other metadata.")
        var protected = corrected[0]
        protected.balloonShape = BalloonShape(bounds: bounds, rows: [.init(y: 0.64, left: 0.21, right: 0.69)])
        try check(lexicon.inferKinds([protected]) == [protected], "Enclosed dialogue became an outside effect.")
        protected = corrected[0]; protected.userDefinedTextKind = true
        try check(lexicon.inferKinds([protected]) == [protected], "Automatic inference changed a reviewed kind.")
        protected = corrected[0]; protected.userDefinedBounds = bounds
        try check(lexicon.inferKinds([protected]) == [protected], "Automatic inference changed a manual region.")
        protected = corrected[0]; protected.textKind = .title
        try check(lexicon.inferKinds([protected]) == [protected], "Automatic inference changed an explicit title.")
        try check(block.originalText == "バタンパタン" && block.textKind == .dialogue, "Refinement mutated input data.")
        let sticky = TextBlock(box: bounds, originalText: "にちっ", translatedText: "야옹", sourceIsVertical: true, textKind: .dialogue)
        var expectedSticky = sticky; expectedSticky.textKind = .soundEffect
        try check(lexicon.inferKinds([sticky]) == [expectedSticky], "Vertical sticky effect retained an automatic dialogue kind.")
        var cat = sticky; cat.originalText = "にゃっ"
        try check(lexicon.inferKinds([cat]) == [cat], "A real cat sound was respelled or classified as a sticky effect.")
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
        try check(lexicon.sourceForms.count > 1_000 && lexicon.meaning(for: "にちゃにちゃ") != nil,
                  "Downloaded effect meanings or automatic forms were not bundled.")
        try check(lexicon.meaning(for: "きっと") != nil && !lexicon.recognizes("きっと"),
                  "An ambiguous ordinary adverb became an automatic effect.")
        for source in ["そろそろ", "ソロソロ", "そろ\nそろ", "にちっと音がした", "にゃっ", ""] {
            try check(!lexicon.recognizes(source), "An adverb, sentence or unrelated cat sound was automatically reclassified: \(source)")
        }
        try check(lexicon.meaning(for: "ニャー")?.contains("meow") == true && lexicon.translation(for: "ニャー") == nil,
                  "Cat sound meaning was confused with the sticky effect family.")
        try check(lexicon.meaning(for: "バシャバシャ") == "splish-splash; with a splash"
                  && lexicon.meaning(for: "パシャパシャ")?.contains("camera shutter") == true,
                  "A camera-only sense leaked to the water-only reading or was lost from its own reading.")
        try check(lexicon.meaning(for: "ヌーヴォー") == nil && !lexicon.recognizes("ヌーヴォー"),
                  "An unrelated reading retained an imported effect meaning.")
        try check(lexicon.recognizes("コロンコロン") && !lexicon.recognizes("コロコロ"),
                  "A noun sense restricted to another reading changed automatic classification.")
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
