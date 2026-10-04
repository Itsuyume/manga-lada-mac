import Foundation
import MangaLadaCore

enum MaskedTextTranslationChecks {
    static func run() throws {
        for (source, target, expected) in [
            ("ポ○モンで遊ぼう。", "포켓몬으로 놀자.", "포켓몬으로 놀자."),
            ("ス○ブラで対戦しよう。", "스매시브라더스로 대전하자.", "스매시브라더스로 대전하자."),
            ("スOブラしよう。", "스매시브라더스 하자.", "스매시브라더스 하자."),
            ("スＯブラやろう。", "스매시브라더스 하자.", "스매시브라더스 하자."),
            ("カ〇ビィのぬいぐるみ", "커비 인형", "커비 인형"),
            ("マ○オのゲーム", "마리오 게임", "마리오 게임"),
            ("マ○オさん", "마○오 씨", "마○오 씨"),
            ("○○さんとポ○モンで遊ぼう。", "○○ 씨와 포켓몬으로 놀자.", "○○ 씨와 포켓몬으로 놀자."),
            ("ス○ブラという店", "스○브라라는 가게", "스○브라라는 가게"),
            ("ス○○ラで遊ぼう。", "스○○라로 놀자.", "스○○라로 놀자."),
            ("ス0ブラで遊ぼう。", "스0브라로 놀자.", "스0브라로 놀자."),
            ("ポ○モンランドで遊ぼう。", "포○몬랜드에서 놀자.", "포○몬랜드에서 놀자."),
            ("○○さん", "○○ 씨", "○○ 씨"),
            ("ドラ◯もん", "도라◯몽", "도라○몽"),
            ("カ〇ビィ", "카〇비", "카○비"),
            ("〇ジャンプ", "◯점프", "○점프"),
            ("○\n○さん", "○○ 씨", "○○ 씨"),
            ("ポ○\nモン", "포○몬", "포○몬"),
            ("山○さんと○○駅", "○○역에서 야마○ 씨", "○○역에서 야마○ 씨"),
            ("二〇二六年に○○さん", "2026년에 ○○ 씨", "2026년에 ○○ 씨"),
            ("二〇二六年", "2026년", "2026년"),
            ("一〇〇円", "100엔", "100엔"),
            ("〇点", "0점", "0점"),
            ("〇ページ", "0페이지", "0페이지"),
            ("〇", "0", "0"),
            ("Oリング", "O링", "O링"),
            ("○を選ぶ。", "○를 고른다.", "○를 고른다.")
        ] {
            let block = makeBlock(source)
            let result = try response(target, block: block)
            var expectedBlock = block; expectedBlock.translatedText = expected
            try require(result == [expectedBlock], "Mask normalization changed source, IDs, geometry or visible text: \(source)")
        }
        for (source, invalid) in [
            ("ポ○モン", "포켓몬"), ("ポ○モン", "포... 블라블라"),
            ("ポ○モン", "포○○몬"), ("○○さん", "○ 씨"),
            ("山○さんと○○駅", "야마○○○역"), ("○\n○さん", "○ 씨"),
            ("〇ジャンプ", "점프"), ("ポ○モン", ""),
            ("ス○ブラしよう。", "스○브라 하자."), ("スOブラしよう。", "스... 블라블라 하자."),
            ("ポ○モンで遊ぼう。", "드래곤볼로 놀자."), ("ス○ブラという店", "스매시브라더스라는 가게"),
            ("○○さんとポ○モンで遊ぼう。", "포켓몬으로 놀자.")
        ] {
            do { _ = try response(invalid, block: makeBlock(source)); throw Failure.failed("Invalid mask output was accepted: \(invalid)") }
            catch TranslationError.invalidPageResponse { }
        }
        let context = makeBlock("ポ○モン"), selected = makeBlock("ありがとう")
        let page = Data(#"{"translations":[{"id":0,"text":"포켓몬","kind":"dialogue"},{"id":1,"text":"고마워","kind":"dialogue"}]}"#.utf8)
        let result = try MangaPageResponse.decode(page, blocks: [context, selected], selectedIDs: [selected.id])
        try require(result[0] == context && result[1].translatedText == "고마워", "Discarded context invalidated a selected translation.")
        print("Masked text passed: circle variants, counts/groups, invented names/filler, dates/zero/Latin O, source/geometry and unselected reviews preserved")
    }
    private static func response(_ text: String, block: TextBlock) throws -> [TextBlock] {
        try MangaNumberedPageResponse.decode("[R0] " + text, blocks: [block])
    }
    private static func makeBlock(_ source: String) -> TextBlock {
        TextBlock(box: TextBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4), originalText: source,
                  translatedText: "기존 검수", textKind: .dialogue, userDefinedTextKind: true)
    }
    private static func require(_ condition: Bool, _ message: String) throws { if !condition { throw Failure.failed(message) } }
    private enum Failure: Error { case failed(String) }
}

extension NetworkBoundaryChecks {
    static func checkMaskedText(session: URLSession) async throws {
        let block = TextBlock(box: TextBox(x: 0.2, y: 0.3, width: 0.2, height: 0.3), originalText: "ポ○モンで遊ぼう。", translatedText: "이전 검수", textKind: .dialogue)
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(GemmaProbe.self, from: Self.body(request))
            try check(body.messages[0].content.contains("[R0] ポケモンで遊ぼう。"), "Known name was not resolved in the request.")
            let text = FixtureProtocol.state.count == 1 ? "[R0] 포... 블라블라" : "[R0] 포켓몬으로 놀자."
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: text))))
        }
        let result = try await pipeline.translateSelected([block.id], in: [block], configuration: LocalTranslatorConfiguration())
        var expected = block; expected.translatedText = "포켓몬으로 놀자."
        try check(result == [expected] && FixtureProtocol.state.count == 2, "Masked name did not recover through one bounded validation retry.")
        FixtureProtocol.state.install { _ in
            (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 포○몬"))))
        }
        do {
            _ = try await pipeline.translate([block], configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Repeated mask loss was silently accepted.")
        } catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 2 && block.translatedText == "이전 검수", "Mask retry loop changed inputs or exceeded request budget.")
        for text in ["포켓몬으로 놀자.", "포○몬으로 놀자."] {
            FixtureProtocol.state.install { request in
                let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
                try check(query?.first(where: { $0.name == "q" })?.value == "ポケモンで遊ぼう。", "Google request did not resolve a known name.")
                return (200, try JSONSerialization.data(withJSONObject: [[[text, "ポケモンで遊ぼう。"]]]))
            }
            do {
                let translated = try await pipeline.translate([block], configuration: LocalTranslatorConfiguration(provider: .googleWeb))
                try check(text.contains("포켓몬") && translated[0].translatedText == text && translated[0].originalText == block.originalText, "Google known-name output changed meaning or the OCR source.")
            } catch TranslationError.invalidPageResponse {
                try check(text.contains("○"), "Google valid known name was rejected.")
            }
        }
        try await checkMaskedPageProviders(session: session, block: block, expected: expected)
        print("Masked network boundary passed: bounded retry, persistent failure, original reviews, Google validation")
    }

    private static func checkMaskedPageProviders(session: URLSession, block: TextBlock, expected: TextBlock) async throws {
        let page = #"{"translations":[{"id":0,"text":"포켓몬으로 놀자.","kind":"dialogue"}]}"#
        FixtureProtocol.state.install { request in
            let body = String(decoding: try Self.body(request), as: UTF8.self)
            try check(body.contains("ポケモンで遊ぼう。"), "JSON page provider received an unresolved known name.")
            if request.url?.host == "generativelanguage.googleapis.com" {
                return (200, try JSONEncoder().encode(GeminiReply(candidates: [.init(content: .init(parts: [.init(text: page)]))])))
            }
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: page))))
        }
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let configurations = [LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: "qwen3.5:9b")),
                              LocalTranslatorConfiguration(provider: .geminiFlashLite, gemini: GeminiConfiguration(apiKey: "fixture-key"))]
        for configuration in configurations {
            let result = try await pipeline.translateSelected([block.id], in: [block], configuration: configuration)
            try check(result == [expected], "JSON page provider changed original spelling, metadata or the required name.")
        }
    }
}
