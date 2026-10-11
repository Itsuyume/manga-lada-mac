import Foundation
import MangaLadaCore

extension TranslationStateTests {
    static func checkTranslationContext() async throws {
        let block = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
                              originalText: "ミナさん、待ってください。", translatedText: "미나 씨, 기다려 주세요.", textKind: .dialogue)
        let fixture = try Fixture(blocks: [block])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let state = fixture.state
        var cached = try unwrap(fixture.cache.load(fingerprint: fixture.keys[0].recognition))
        cached.imageFingerprint = fixture.keys[0].translation
        try fixture.cache.save(cached)
        state.startTranslation(onlyCurrent: true)
        await state.job?.value
        _ = try unwrap(state.results[0])
        check(state.translationContext(before: 2).contains("미나 씨, 기다려 주세요."), "App lost context across an unprocessed blank page.")
        check(state.translationContext(before: 0).isEmpty, "Current page became its own context.")
        let saved = state.results
        state.failures[0] = "Failed retry"
        check(state.translationContext(before: 2).isEmpty && state.results.count == saved.count,
              "App reused a failed page as successful context or changed saved results.")
        try fixture.checkSources()
        print("PASS app context uses saved prior dialogue, skips failures and preserves sources")
    }
}
