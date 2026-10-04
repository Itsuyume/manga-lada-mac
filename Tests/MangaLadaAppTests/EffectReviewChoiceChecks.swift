import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension TranslationStateTests {
    static func checkEffectReviewChoices() async throws {
        let effect = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.7, height: 0.2), originalText: "パチパチ",
                               textKind: .soundEffect, rotationDegrees: 10, effectStyleID: "impact")
        let neighbor = TextBlock(box: TextBox(x: 0.1, y: 0.5, width: 0.7, height: 0.2), originalText: "手をたたいた。", textKind: .caption)
        let fixture = try Fixture(blocks: [effect, neighbor]), state = fixture.state
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        state.startTranslation(onlyCurrent: true)
        await state.job?.value
        let baseline = try unwrap(state.currentReview), lexicon = try unwrap(state.effectLexicon)
        let spelling = try unwrap(lexicon.reviewOptions(for: effect.originalText).first { $0.context == "박수" })
        state.editReviewBlock(neighbor.id) { $0.translatedText = "손뼉을 쳤다." }
        let before = try unwrap(state.currentReview)
        let recognition = fixture.cache.cacheFileURL(fingerprint: fixture.keys[0].recognition)
        let originalRecognition = try Data(contentsOf: recognition)
        state.editReviewBlock(effect.id) { $0.translatedText = spelling.korean }
        let draft = try unwrap(state.currentReview)
        var expected = before; expected.blocks[0].translatedText = "짝짝"
        check(draft == expected && draft.blocks[1] == before.blocks[1], "Choosing an effect changed source, region, style or another review.")
        check(try state.reviewStore.load(for: baseline) == draft, "Chosen spelling was not persisted as a review draft.")
        check(try fixture.cache.load(fingerprint: baseline.imageFingerprint) == nil && state.results.isEmpty,
              "Choosing a spelling prematurely committed the translation or image.")
        state.isBusy = true
        state.editReviewBlock(effect.id) { $0.translatedText = "덜덜" }
        check(state.currentReview == draft, "A busy page accepted a review choice.")
        state.isBusy = false
        state.select(1)
        state.editReviewBlock(effect.id) { $0.translatedText = "덜덜" }
        state.select(0)
        check(state.currentReview == draft, "A stale choice changed another page.")
        state.discardCurrentReview()
        check(state.currentReview == baseline && !state.hasCurrentReview, "Cancel did not restore the baseline after an effect choice.")
        try state.saveReview(draft, comparedTo: baseline, at: 0)
        try state.updateCurrentTranslation(draft)
        let saved = try unwrap(state.currentResult)
        check(saved.translation.blocks[0].translatedText == "짝짝" && saved.translation.blocks[1].translatedText == "손뼉을 쳤다.",
              "Applying chosen spelling did not preserve the neighboring review.")
        check(saved.translation.blocks[0].effectStyleID == "impact" && saved.translation.blocks[0].rotationDegrees == 10,
              "Applying a choice changed the effect style or rotation.")
        check(try Data(contentsOf: recognition) == originalRecognition, "Review choice modified the OCR cache.")
        check(try state.reviewStore.load(for: baseline) == nil && !state.hasCurrentReview, "Applied choice remained pending.")
        check(try !Data(contentsOf: saved.renderedImageURL).isEmpty, "Applying choice did not save an image.")
        try fixture.checkSources()
        print("PASS effect review choices: source/style/neighbor preservation, persistence, busy/stale page, cancel and apply; no model key")
    }
}
