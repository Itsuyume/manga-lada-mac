import Foundation
import MangaLadaCore

enum TermDisambiguationChecks {
    static func run() async throws {
        let source = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.7, height: 0.2),
                              originalText: "辞書では、マンコは女性器の俗語です。", textKind: .caption)
        var cached = source; cached.translatedText = "음모를 뜻하는 속어야."
        try check(JapaneseTermDisambiguation.reviewMessage(for: cached) != nil, "A cached terminology error had no review notice.")
        cached.keepsOriginal = true
        try check(JapaneseTermDisambiguation.reviewMessage(for: cached) == nil, "Original-retained artwork was flagged as translated text.")
        for original in [source.originalText, "医学用語の陰茎。", "女性器を表すまんこ。", "男性器を表すちんちん。"] {
            var block = source; block.originalText = original
            do { _ = try MangaNumberedPageResponse.decode("[R0] 음모를 뜻하는 용어.", blocks: [block]); throw Failure.wrongMeaningAccepted }
            catch TranslationError.invalidPageResponse { }
        }
        var hair = source; hair.originalText = "陰毛は毛を表す言葉です。"
        do { _ = try MangaNumberedPageResponse.decode("[R0] 머리카락을 뜻하는 단어야.", blocks: [hair]); throw Failure.wrongMeaningAccepted }
        catch TranslationError.invalidPageResponse { }
        for (original, translated) in [(source.originalText, "사전에서는 여성기를 가리키는 속어야."),
            ("陰毛についての説明。", "음모에 대한 설명."),
            ("マンコと陰毛は異なる。", "여성기와 음모는 서로 달라."),
            ("陰毛と頭髪は異なる。", "음모와 머리카락은 서로 달라."),
            ("マンコ・カパックの陰謀。", "만코 카파크의 음모."),
            ("陰茎の説明と陰謀という語。", "음경의 설명과 음모라는 단어.")] {
            var block = source; block.originalText = original
            let result = try MangaNumberedPageResponse.decode("[R0] " + translated, blocks: [block])
            try check(result[0].translatedText == translated && result[0].id == source.id, "Terminology validation rewrote valid text or identity.")
        }
        try await checkRetry(source)
        print("Terminology checks passed: organ/hair distinction, mixed meanings, proper names, bounded retry and persistent-failure rejection")
    }

    private static func checkRetry(_ source: TextBlock) async throws {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        FixtureProtocol.state.install { request in
            let probe = try JSONDecoder().decode(Probe.self, from: NetworkBoundaryChecks.body(request))
            if FixtureProtocol.state.count == 2 {
                try check(probe.messages[0].content.contains("체모"), "The correction request lost the meaning error.")
            }
            let output = FixtureProtocol.state.count == 1 ? "음모를 뜻하는 속어야." : "여성기를 가리키는 속어야."
            return try FixtureProtocol.ollamaReply("[R0] " + output)
        }
        let result = try await TranslateGemmaPageTranslator(session: session).translatePage([source])
        try check(FixtureProtocol.state.count == 2 && result[0].translatedText == "여성기를 가리키는 속어야.", "A clear word-meaning error was saved without correction.")
        FixtureProtocol.state.install { _ in try FixtureProtocol.ollamaReply("[R0] 음모를 뜻하는 속어야.") }
        do { _ = try await TranslateGemmaPageTranslator(session: session).translatePage([source]); throw Failure.wrongMeaningAccepted }
        catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 2, "A persistent terminology error retried without a bound.")
    }
    private struct Probe: Decodable { let messages: [NetworkBoundaryChecks.Message] }
    private static func check(_ value: Bool, _ message: String) throws { try NetworkBoundaryChecks.check(value, message) }
    private enum Failure: Error { case wrongMeaningAccepted }
}
