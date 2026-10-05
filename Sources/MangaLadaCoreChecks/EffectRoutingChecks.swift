import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkEffectRouting(session: URLSession) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let box = TextBox(x: 0.2, y: 0.2, width: 0.1, height: 0.2)
        let stale = TextBlock(box: box, originalText: "にちゃにちゃ", translatedText: "야옹", sourceIsVertical: true, textKind: .dialogue)
        var neighbor = stale; neighbor.id = UUID(); neighbor.box.y = 0.6; neighbor.translatedText = "직접 검수한 문구"
        FixtureProtocol.state.install { request in
            let payload = try JSONDecoder().decode(EffectPrompt.self, from: body(request))
            let content = payload.messages.map(\.content).joined(separator: "\n")
            try check(content.contains("R0: sound effect") && content.contains("Sticky or slimy")
                      && content.contains("接着剤をはがした。"), "Effect request lost detected kind, dictionary meaning or prior context.")
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 쩍\n[R1] 모델이 바꾼 주변 문구"))))
        }
        let selected = try await pipeline.translateSelected([stale.id], in: [stale, neighbor],
            configuration: LocalTranslatorConfiguration(), previousContext: "接着剤をはがした。")
        var expected = stale; expected.textKind = .soundEffect; expected.translatedText = "쩍"
        try check(selected == [expected, neighbor], "Effect retry lost source identity, geometry or a neighboring review, or retained the stale kind.")
        try check(stale.textKind == .dialogue && stale.translatedText == "야옹", "Effect retry mutated its source.")
        try check(FixtureProtocol.state.count == 1, "Effect dictionary caused extra model calls.")

        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Known fixed effects reached the model.") }
        let click = TextBlock(box: box, originalText: "にちっ", textKind: .dialogue)
        let direct = try await pipeline.translate([click], configuration: LocalTranslatorConfiguration())
        try check(direct.count == 1 && direct[0].id == click.id && direct[0].textKind == .soundEffect
                  && direct[0].translatedText == "질척" && FixtureProtocol.state.count == 0,
                  "Known effect was not applied locally without a model call.")
        for source in ["に\nちっ", "ニ\r\nチッ！", " に ちっ。 "] {
            var wrapped = click; wrapped.originalText = source; wrapped.translatedText = "야옹"
            let corrected = try await pipeline.translateSelected([wrapped.id], in: [wrapped, neighbor], configuration: LocalTranslatorConfiguration())
            var expected = wrapped; expected.textKind = .soundEffect; expected.translatedText = "질척"
            try check(corrected == [expected, neighbor] && FixtureProtocol.state.count == 0,
                      "OCR whitespace missed the fixed effect or changed source/neighbor without a selection.")
        }
        let simple = ["バシャバシャ", "ポタポタ", "ガヤガヤ", "バビュン", "ばびゅん", " ﾊﾞﾋﾞｭ\nﾝ！ "]
            .map { TextBlock(box: box, originalText: $0, textKind: .dialogue) }
        let locallyTranslated = try await pipeline.translate(simple, configuration: LocalTranslatorConfiguration())
        try check(locallyTranslated.map(\.translatedText) == ["첨벙첨벙", "똑똑", "웅성웅성", "슈웅", "슈웅", "슈웅"]
                  && locallyTranslated.allSatisfy({ $0.textKind == .soundEffect })
                  && locallyTranslated.map(\.id) == simple.map(\.id) && FixtureProtocol.state.count == 0,
                  "Reading-specific defaults changed identities or called the model.")
        let handwritten = ["ごろん", "もじ．．．"].map { TextBlock(box: box, originalText: $0, textKind: .soundEffect, userDefinedTextKind: true) }
        let repaired = try await pipeline.translate(handwritten, configuration: LocalTranslatorConfiguration())
        try check(repaired.map(\.translatedText) == ["뒹굴", "꼼지락"] && FixtureProtocol.state.count == 0,
                  "Short printed effects were mistranslated as stomach noise or dialogue.")
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        let ordinary = TextBlock(box: box, originalText: "もじ", textKind: .dialogue)
        try check(lexicon.inferKinds([ordinary]) == [ordinary], "The homophone for letters became an automatic effect.")
        try await checkReadingSpecificContext(pipeline: pipeline, box: box)
        try check(try await pipeline.translateSelected([], in: [stale], configuration: LocalTranslatorConfiguration()) == [stale],
                  "Empty selection reclassified a cache entry.")
        try await checkEffectOverrides(session: session, pipeline: pipeline, stale: stale)
        print("Effect routing passed: selected legacy classification, dictionary context, no-call fixed effects, explicit overrides and neighbor preservation")
    }

    private static func checkReadingSpecificContext(pipeline: TranslationPipeline, box: TextBox) async throws {
        FixtureProtocol.state.install { request in
            let prompt = try JSONDecoder().decode(EffectPrompt.self, from: body(request))
            let content = prompt.messages.map(\.content).joined(separator: "\n")
            try check(content.contains("camera shutter"), "The camera reading lost its specific meaning.")
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 찰칵찰칵"))))
        }
        let camera = TextBlock(box: box, originalText: "パシャパシャ", textKind: .soundEffect)
        let translated = try await pipeline.translate([camera], configuration: LocalTranslatorConfiguration())
        try check(translated.first?.translatedText == "찰칵찰칵" && translated.first?.id == camera.id && FixtureProtocol.state.count == 1,
                  "A context-dependent camera reading used the fixed water sound.")
    }

    private static func checkEffectOverrides(session: URLSession, pipeline: TranslationPipeline, stale: TextBlock) async throws {
        for manual in [true, false] {
            var enclosed = stale
            if manual { enclosed.userDefinedTextKind = true }
            else { enclosed.balloonShape = BalloonShape(bounds: stale.box, rows: [.init(y: 0.3, left: 0.21, right: 0.29)]) }
            FixtureProtocol.state.install { _ in
                (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 직접 말한 소리"))))
            }
            let translated = try await pipeline.translateSelected([enclosed.id], in: [enclosed], configuration: LocalTranslatorConfiguration())
            var expected = enclosed; expected.translatedText = "직접 말한 소리"
            try check(translated == [expected], "Manual or enclosed speech was reclassified as an outside effect.")
        }
        FixtureProtocol.state.install { _ in (503, Data()) }
        do {
            _ = try await pipeline.translateSelected([stale.id], in: [stale], configuration: LocalTranslatorConfiguration())
            throw BoundaryCheckError.failed("Effect failure was hidden by the glossary.")
        } catch TranslationError.httpStatus(503) { }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.translate([stale], configuration: LocalTranslatorConfiguration())
        }
        let before = FixtureProtocol.state.count
        do { _ = try await task.value; throw BoundaryCheckError.failed("Cancelled effect translation completed.") }
        catch is CancellationError { }
        try check(FixtureProtocol.state.count == before, "Cancellation still called a model.")
    }

    private struct EffectPrompt: Decodable { let messages: [Message] }
}
