import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension TranslationStateTests {
    static func checkOriginalRegions() async throws {
        let first = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.7, height: 0.2), originalText: "また明日。",
            translatedText: "내일 봐!", textKind: .dialogue)
        let second = TextBlock(box: .init(x: 0.1, y: 0.5, width: 0.7, height: 0.2), originalText: "ありがとう",
            translatedText: "고마워!", textKind: .dialogue)
        let fixture = try Fixture(blocks: [first, second]), state = fixture.state
        defer { state.clearLetteringPreview(); try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.cache.save(PageTranslation(imageURL: fixture.sources[0].0, imageFingerprint: fixture.keys[0].translation,
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [first, second]))
        state.startTranslation(onlyCurrent: true); await state.job?.value
        let baseline = try unwrap(state.currentResult), pixels = try Data(contentsOf: baseline.renderedImageURL)
        let clean = try Data(contentsOf: baseline.cleanImageURL)
        state.beginLetteringPlacement(first.id)
        state.setKeepsOriginal(first.id, true); await state.letteringPreviewTask?.value
        let draft = try unwrap(state.currentReview)
        check(draft.blocks[0].keepsOriginal == true && draft.blocks[0].translatedText == first.translatedText
              && draft.blocks[1] == baseline.translation.blocks[1], "Region deletion destroyed undo text or its neighbor.")
        check(state.letteringPreviewURL != nil && state.letteringPreviewError == nil && state.placementBlockID == nil,
              "Original restoration did not preview or retained an active placement gesture.")
        check(try Data(contentsOf: baseline.renderedImageURL) == pixels && fixture.cache.load(fingerprint: draft.imageFingerprint) == baseline.translation,
              "Staging original restoration changed committed pixels/cache.")
        state.moveLettering(first.id, by: .init(width: 0.1, height: 0.1)); state.beginLetteringPlacement(first.id)
        state.retranslateBlock(in: draft, at: 0)
        check(state.currentReview == draft && state.job == nil && state.placementBlockID == nil, "Original-only region could still be moved/retranslated.")
        check(try state.reviewStore.load(for: baseline.translation) == draft, "Original-only draft did not persist.")
        state.discardCurrentReview()
        check(state.currentReview == baseline.translation && state.letteringPreviewURL == nil, "Cancel did not restore the saved translation.")
        state.setKeepsOriginal(first.id, true)
        try state.updateCurrentTranslation(unwrap(state.currentReview))
        let saved = try unwrap(state.currentResult)
        check(saved.translation.blocks[0].keepsOriginal == true && !state.hasCurrentReview, "Applied deletion was not committed.")
        check(try Data(contentsOf: saved.renderedImageURL) != pixels && Data(contentsOf: saved.cleanImageURL) == clean,
              "Deletion failed to change output or mutated the clean source.")
        let reopened = try await state.processor.process(imageURL: fixture.sources[0].0, destinationURL: saved.renderedImageURL,
            configuration: state.configuration, typography: state.typography, bookTitle: state.title)
        check(reopened.translation == saved.translation, "Reopening the translation lost original-only choice.")
        state.setKeepsOriginal(first.id, false)
        try state.updateCurrentTranslation(unwrap(state.currentReview))
        check(try Data(contentsOf: saved.renderedImageURL) == pixels, "Undo changed the original translated image.")
        let current = try unwrap(state.currentReview)
        state.isBusy = true; state.setKeepsOriginal(first.id, true); state.isBusy = false
        check(state.currentReview == current, "Busy guard allowed concurrent deletion.")
        state.setKeepsOriginal(UUID(), true)
        check(state.currentReview == current && state.errorMessage != nil, "Stale selection changed another region or hid the error.")
        state.errorMessage = nil
        state.setKeepsOriginal(first.id, true); state.setKeepsOriginal(second.id, true)
        try state.updateCurrentTranslation(unwrap(state.currentReview))
        state.startTranslation(onlyCurrent: true, force: true); await state.job?.value
        check(state.failures.isEmpty && state.currentReview?.blocks.allSatisfy { $0.keepsOriginal == true } == true,
              "Forced retry called an unconfigured model or lost original-only decisions.")
        try fixture.checkSources(); try fixture.checkManifest(completed: [0], failures: [])
        try await checkFailedOriginalRegion()
        print("PASS original-region controls: preview/apply/cancel/undo/reopen/forced retry, no model requests, busy/stale ID, pending failure recovery")
    }

    private static func checkFailedOriginalRegion() async throws {
        let block = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.7, height: 0.2), originalText: "また明日。", textKind: .dialogue)
        let fixture = try Fixture(blocks: [block]), state = fixture.state
        defer { state.clearLetteringPreview(); try? FileManager.default.removeItem(at: fixture.root) }
        state.startTranslation(onlyCurrent: true); await state.job?.value
        check(state.pendingPages[0] != nil && state.failures[0] != nil, "Missing-key fixture did not produce a pending failure.")
        state.setKeepsOriginal(block.id, true)
        let draft = try unwrap(state.currentReview)
        check(draft.untranslatedBlockIDs.isEmpty && draft.blocks[0].translatedText.isEmpty, "Excluded blank text blocks completion.")
        try state.updateCurrentTranslation(draft)
        check(state.completed == [0] && state.failures.isEmpty && state.pendingPages.isEmpty, "Preserving failed region did not recover the page.")
        try fixture.checkSources(); try fixture.checkManifest(completed: [0], failures: [])
    }
}
