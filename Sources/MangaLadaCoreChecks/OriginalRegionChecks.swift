import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkOriginalRegions(session: URLSession) async throws {
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean, session: session)
        let box = TextBox(x: 0.1, y: 0.1, width: 0.3, height: 0.2)
        let kept = TextBlock(box: box, originalText: "また明日。", translatedText: "이전 검수", keepsOriginal: true, textKind: .dialogue)
        let active = TextBlock(box: .init(x: 0.5, y: 0.1, width: 0.3, height: 0.2), originalText: "ありがとう", textKind: .dialogue)
        let configuration = LocalTranslatorConfiguration(interpretMaskedText: false)
        FixtureProtocol.state.install { _ in throw BoundaryCheckError.failed("Original-only selection reached the model.") }
        try check(try await pipeline.translate([kept], configuration: configuration) == [kept], "Original-only page changed.")
        try check(try await pipeline.translateSelected([kept.id], in: [kept, active], configuration: configuration) == [kept, active],
                  "Selected original-only region changed its neighbor.")
        try check(FixtureProtocol.state.count == 0, "Original-only request had a network side effect.")
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(GemmaProbe.self, from: Self.body(request))
            try check(body.messages[0].content.contains("[R0] ありがとう") && !body.messages[0].content.contains(kept.originalText),
                      "Explicitly excluded text was still sent to the model.")
            return (200, try JSONEncoder().encode(ChatReply(message: Message(role: "assistant", content: "[R0] 고마워"))))
        }
        let mixed = try await pipeline.translate([kept, active], configuration: configuration)
        try check(mixed.first(where: { $0.id == kept.id }) == kept && mixed.first(where: { $0.id == active.id })?.translatedText == "고마워",
                  "Mixed page lost region identity or original choice.")
        try check(mixed.map(\.id) == MangaReadingOrder.sorted([kept, active]).map(\.id), "Mixed full-page translation lost reading order.")
        let selected = try await pipeline.translateSelected([kept.id, active.id], in: [kept, active], configuration: configuration)
        try check(selected.map(\.id) == [kept.id, active.id] && MangaReadingOrder.sorted(selected) == mixed && FixtureProtocol.state.count == 2,
                  "Selected original region was retranslated/reordered or extra requests were made.")
        try checkOriginalRegionPersistence(kept: kept, active: active)
        print("Original-region checks passed: no model for excluded text, stable identity, cache compatibility, review persistence and undo")
    }

    private static func checkOriginalRegionPersistence(kept: TextBlock, active: TextBlock) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("original-review-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TranslationReviewStore(directory: root)
        var baseline = PageTranslation(imageURL: root.appendingPathComponent("source.png"), imageFingerprint: "original-review",
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [kept, active])
        baseline.blocks[0].keepsOriginal = nil
        let legacy = try JSONEncoder().encode(baseline)
        try check(!String(decoding: legacy, as: UTF8.self).contains("keepsOriginal"), "Legacy fixture contains new flag.")
        try check(try JSONDecoder().decode(PageTranslation.self, from: legacy) == baseline, "Legacy cache lost compatibility.")
        var edited = baseline; edited.blocks[0] = kept; edited.blocks[0].translatedText = ""
        try store.save(edited, comparedTo: baseline)
        try check(try store.load(for: baseline) == edited, "Original choice was not restored from draft storage.")
        try check(edited.untranslatedBlockIDs == [active.id], "Excluded empty translation still blocks completion.")
        var refreshed = baseline; refreshed.blocks[1].translatedText = "새 검수"; refreshed.blocks[0].translatedText = "새 문구"
        let merged = try store.load(for: refreshed)
        try check(merged?.blocks[0].keepsOriginal == true && merged?.blocks[1] == refreshed.blocks[1], "Fieldwise review overwrote an unrelated change.")
        try store.save(baseline, comparedTo: edited)
        try check(try store.load(for: edited) == baseline, "Undo did not persist the original-preservation change.")
        var moved = kept; moved.textOffset = .init(x: 0.2, y: 0.2); moved.textLayoutBounds = active.box
        try check(LetteringPreferences.displayBounds(for: moved) == kept.box, "Original marker follows translated lettering movement.")
    }
}
