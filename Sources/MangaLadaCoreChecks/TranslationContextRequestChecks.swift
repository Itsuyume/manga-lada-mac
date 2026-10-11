import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkHistoryRequests(session: URLSession) async throws {
        let previous = PageTranslation(imageURL: URL(fileURLWithPath: "previous.png"), imageFingerprint: "previous",
            sourceLanguage: .japanese, targetLanguage: .korean,
            blocks: [TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1), originalText: "ミナさん、座ってください。",
                               translatedText: "미나 씨, 앉으세요.", textKind: .dialogue)])
        let history = MangaTranslationContext.previousPages([0: previous], before: 2)
        let blocks = [TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.3, height: 0.2), originalText: "ありがとうございます。", textKind: .dialogue)]
        FixtureProtocol.state.install { request in
            let probe = try JSONDecoder().decode(GemmaProbe.self, from: body(request))
            try check(probe.messages[0].content.contains(history), "Whole/selected translation lost bounded prior-page context at HTTP boundary.")
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 감사합니다."))))
        }
        let translated = try await OllamaPageTranslator(session: session).translatePage(blocks, previousContext: history)
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let selected = try await pipeline.translateSelected([blocks[0].id], in: blocks,
            configuration: LocalTranslatorConfiguration(), previousContext: history)
        try check(translated[0].translatedText == "감사합니다." && selected == translated && FixtureProtocol.state.count == 2,
                  "History changed output mapping or introduced extra requests.")
        FixtureProtocol.state.install { request in
            let probe = try JSONDecoder().decode(HistoryJSONProbe.self, from: body(request))
            try check(probe.messages.last?.content.contains(history) == true, "JSON translation provider dropped prior-page context.")
            let response = #"{"translations":[{"id":0,"text":"감사합니다.","kind":"dialogue"}]}"#
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: response))))
        }
        let structured = try await OllamaPageTranslator(configuration: OllamaConfiguration(model: "qwen3.5:9b"), session: session)
            .translatePage(blocks, previousContext: history)
        try check(structured == translated, "Structured provider lost translation IDs or geometry with history.")
        print("History request checks passed: real page/selection pipeline and two HTTP provider formats receive intact context")
    }
    private struct HistoryJSONProbe: Decodable { let messages: [Message] }
}
