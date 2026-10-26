import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkMaskedRouting(session: URLSession) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("masked-routing-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let masked = contextBlock("スOブラで対戦しよう。", y: 0.1)
        let neighbor = contextBlock("コントローラーを二つ持ってきた。", y: 0.5)
        try check(MaskedTextTranslation.reviewMessage(for: masked) != nil, "Stale cached wording was not flagged.")
        for source in ["", "○○さん", "二〇二六年", "〇円", "Oリング", "パッキンOリング", "血液O型", "CEO", "はい。"] {
            try check(!MaskedTextTranslation.requiresContextTranslation(source), "A non-word mask triggered Qwen: " + source)
        }
        for source in ["スOブラで対戦しよう。", "スＯブラ", "お○ぎり", "お◯ぎり", "お〇ぎり"] {
            try check(MaskedTextTranslation.requiresContextTranslation(source), "A supported word mask was missed: " + source)
        }
        FixtureProtocol.state.install { request in
            let probe = try JSONDecoder().decode(MaskedRouteProbe.self, from: body(request))
            try check(probe.model == OllamaConfiguration.defaultModel && probe.format == nil, "Masked dialogue bypassed the selected TranslateGemma model.")
            try check(probe.messages.contains { $0.content.contains(neighbor.originalText) }, "Selected translation lost neighboring context.")
            let content = "[R0] 스매시브라더스로 대전하자.\n[R1] discarded context"
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
        let translated = try await contextPipeline(root, session: session).translateSelected([masked.id], in: [masked, neighbor],
            configuration: LocalTranslatorConfiguration(interpretMaskedText: true))
        try check(translated[0].translatedText == "스매시브라더스로 대전하자." && translated[1] == neighbor,
                  "Targeted translation did not repair the selected wording or changed a reviewed neighbor.")
        try check(translated[0].id == masked.id && translated[0].box == masked.box && translated[0].originalText == masked.originalText,
                  "Targeted translation changed source identity or geometry.")
        try check(FixtureProtocol.state.count == 1, "A catalogued name required extra interpretation calls.")
        try check(MaskedTextTranslation.reviewMessage(for: translated[0]) == nil
                  && translated[0].maskedTextInterpretation?.translationModel == OllamaConfiguration.defaultModel,
                  "A fresh selected-model translation retained the stale-cache warning.")
        try await checkMixedMaskedRouting(root: root, session: session, masked: masked, neighbor: neighbor)
        try await checkConfiguredMaskedModel(root: root, session: session, masked: masked, neighbor: neighbor)
        try await checkMaskedRefresh(root: root, session: session)
        print("Masked routing passed: selected model, one mixed-page request, neighbor preservation, old-result notice, mask/Latin/zero boundaries and targeted refresh")
    }

    private static func checkMixedMaskedRouting(root: URL, session: URLSession, masked: TextBlock, neighbor: TextBlock) async throws {
        FixtureProtocol.state.install { request in
            let probe = try JSONDecoder().decode(MaskedRouteProbe.self, from: body(request))
            try check(probe.model == OllamaConfiguration.defaultModel && probe.format == nil, "Mixed page bypassed the selected model.")
            let content = "[R0] 스매시브라더스로 대전하자.\n[R1] 컨트롤러를 두 개 가져왔어."
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
        let result = try await contextPipeline(root, session: session).translate([neighbor, masked],
            configuration: LocalTranslatorConfiguration(interpretMaskedText: true))
        try check(FixtureProtocol.state.count == 1 && result[0].id == neighbor.id && result[1].id == masked.id
                  && result[0].translatedText == "컨트롤러를 두 개 가져왔어." && result[1].translatedText.contains("스매시브라더스"),
                  "Mixed routing lost order or model assignment.")
    }

    private static func checkConfiguredMaskedModel(root: URL, session: URLSession, masked: TextBlock, neighbor: TextBlock) async throws {
        FixtureProtocol.state.install { request in
            let probe = try JSONDecoder().decode(MaskedRouteProbe.self, from: body(request))
            try check(probe.model == OllamaConfiguration.visionModel && probe.format?.properties.translations?.maxItems == 2,
                      "Explicitly selected Qwen was overridden or lost page context.")
            let content = #"{"translations":[{"id":0,"text":"스매시브라더스로 대전하자.","kind":"dialogue"},{"id":1,"text":"未選択","kind":"dialogue"}]}"#
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: content))))
        }
        let configuration = LocalTranslatorConfiguration(ollama: OllamaConfiguration(model: OllamaConfiguration.visionModel), interpretMaskedText: true)
        let result = try await contextPipeline(root, session: session).translateSelected([masked.id], in: [masked, neighbor], configuration: configuration)
        try check(FixtureProtocol.state.count == 1 && result[1] == neighbor
                  && result[0].maskedTextInterpretation?.translationModel == OllamaConfiguration.visionModel,
                  "Explicit model selection changed neighboring reviews or recorded incorrect provenance.")
    }

    private static func checkMaskedRefresh(root: URL, session: URLSession) async throws {
        let folder = root.appendingPathComponent("refresh"), block = contextBlock("お○ぎりを食べよう。", y: 0.1)
        let configuration = LocalTranslatorConfiguration(interpretMaskedText: true)
        let pipeline = contextPipeline(folder, session: session)
        installContextResponse(terms: #"{"terms":[]}"#, translation: "[R0] 오○기리를 먹자.")
        let stale = try await pipeline.translate([block], configuration: configuration)
        let cache = folder.appendingPathComponent("masked-context-v1.json")
        let old = try Data(contentsOf: cache)
        installContextResponse(terms: #"{"terms":[{"masked":"お○ぎり","expanded":"おにぎり"}]}"#, translation: "[R0] 주먹밥을 먹자.")
        let fresh = try await pipeline.translateSelected([block.id], in: stale, configuration: configuration, refreshMaskedContext: true)
        try check(FixtureProtocol.state.count == 2 && fresh[0].translatedText == "주먹밥을 먹자."
                  && fresh[0].maskedTextInterpretation?.japanese == "おにぎりを食べよう。"
                  && fresh[0].maskedTextInterpretation?.usedCachedInterpretation == false,
                  "Explicit refresh reused the previous abstention or skipped the selected translator.")
        let updated = try Data(contentsOf: cache)
        try check(updated != old, "Refreshed interpretation did not replace its exact cache entry.")
        let again = try await contextPipeline(folder, session: session).translate([block], configuration: configuration)
        try check(FixtureProtocol.state.count == 3 && again[0].maskedTextInterpretation?.usedCachedInterpretation == true,
                  "Fresh interpretation was not reusable after reopening.")
        installContextResponse(terms: #"{"terms":[{"masked":"お○ぎり","expanded":"おすし"}]}"#, translation: "[R0] 오○기리를 먹자.")
        let failed = try await pipeline.translateSelected([block.id], in: fresh, configuration: configuration, refreshMaskedContext: true)
        try check(FixtureProtocol.state.count == 3 && failed[0].maskedTextInterpretation?.message.contains("실패") == true,
                  "Failed refresh silently reused an old hypothesis.")
        try check(try Data(contentsOf: cache) == updated, "Failed refresh overwrote a valid cache.")
        let latinMask = contextBlock("おOぎりを食べよう。", y: 0.1)
        let failedLatin = try await pipeline.translate([latinMask], configuration: configuration, refreshMaskedContext: true)
        try check(failedLatin[0].maskedTextInterpretation?.japanese == nil
                  && MaskedTextTranslation.reviewMessage(for: failedLatin[0]) != nil,
                  "O normalization was mistaken for a resolved meaning or hid a failed interpretation.")
        let calls = FixtureProtocol.state.count
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pipeline.translateSelected([block.id], in: fresh, configuration: configuration, refreshMaskedContext: true)
        }
        do { _ = try await task.value; throw BoundaryCheckError.failed("Cancelled refresh completed.") }
        catch is CancellationError { }
        try check(FixtureProtocol.state.count == calls && (try Data(contentsOf: cache)) == updated, "Cancelled refresh wrote cache or called a model.")
    }

    struct MaskedRouteProbe: Decodable {
        let model: String
        let messages: [Message]
        let format: Schema?
        struct Schema: Decodable {
            let properties: Properties
            struct Properties: Decodable { let translations: Items?; let terms: Items? }
            struct Items: Decodable { let maxItems: Int? }
        }
    }
}
