import Foundation
import MangaLadaCore

extension TranslationStateTests {
    static func checkLetteringControls() async throws {
        let block = TextBlock(box: .init(x: 0.2, y: 0.15, width: 0.6, height: 0.5), originalText: "ドキドキ",
                              translatedText: "두근두근", sourceIsVertical: true, detectedFontSize: 34, textKind: .soundEffect)
        let fixture = try Fixture(blocks: [block]), state = fixture.state
        defer { state.clearLetteringPreview(); try? FileManager.default.removeItem(at: fixture.root) }
        let cached = PageTranslation(imageURL: fixture.sources[0].0, imageFingerprint: fixture.keys[0].translation,
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [block])
        try fixture.cache.save(cached)
        state.startTranslation(onlyCurrent: true); await state.job?.value
        let original = try unwrap(state.currentResult), pixels = try Data(contentsOf: original.renderedImageURL)
        let cleanPixels = try Data(contentsOf: original.cleanImageURL)
        for value in stride(from: 0.8, through: 1.2, by: 0.05) {
            state.editReviewBlock(block.id) { $0.fontScale = value; $0.textDirection = .horizontal }
            state.scheduleLetteringPreview()
        }
        await state.letteringPreviewTask?.value
        let preview = try unwrap(state.letteringPreviewURL)
        check(state.letteringPreviewError == nil && FileManager.default.fileExists(atPath: preview.path), "Live lettering preview failed.")
        check(try Data(contentsOf: original.renderedImageURL) == pixels, "Preview overwrote committed output.")
        check(try fixture.cache.load(fingerprint: cached.imageFingerprint) == original.translation, "Preview committed the translation cache.")
        state.moveLettering(block.id, by: .init(width: 0.05, height: 0.05))
        await state.letteringPreviewTask?.value
        check(state.currentReview?.blocks[0].textOffset == .init(x: 0.05, y: 0.05), "Drag movement did not accumulate in the review.")
        let savedDraft = try unwrap(state.currentReview)
        state.moveLettering(block.id, by: .init(width: 4, height: 0))
        check(state.currentReview == savedDraft && state.errorMessage != nil, "Invalid drag was accepted or destroyed the draft.")
        state.errorMessage = nil
        state.beginLetteringPlacement(block.id)
        state.selectRegion(.init(x: 0.25, y: 0.2, width: 0.4, height: 0.35))
        check(state.selectedBlockID == block.id && state.selectedRegionNumbers == [1], "Moving placement lost the selected region identity.")
        state.stageLetteringPlacement(); await state.letteringPreviewTask?.value
        let draft = try unwrap(state.currentReview)
        check(draft.blocks[0].textLayoutBounds != nil && draft.blocks[0].textOffset == nil
              && draft.blocks[0].userDefinedBounds == block.userDefinedBounds, "Placement changed recognition/erasure bounds or retained stale movement.")
        check(draft.blocks[0].originalText == block.originalText && draft.blocks[0].translatedText == block.translatedText,
              "Placement reran recognition/translation.")
        try state.updateCurrentTranslation(draft)
        check(state.letteringPreviewURL == nil && state.letteringPreviewTask == nil && !FileManager.default.fileExists(atPath: preview.path),
              "Apply retained preview image/task resources.")
        check(state.currentResult?.translation.blocks[0].textDirection == .horizontal, "Applied lettering lost its direction.")
        check(try Data(contentsOf: original.cleanImageURL) == cleanPixels, "Typesetting edits changed erased source pixels.")
        state.scheduleLetteringPreview(); state.select(1); await Task.yield()
        check(state.letteringPreviewURL == nil && state.letteringPreviewTask == nil, "Stale preview survived page navigation.")
        try fixture.checkSources()
        try await checkLetteringTaskLifetime()
        print("PASS lettering controls: latest preview only, no model calls, drag identity, invalid input, cache/source isolation, apply/navigation cleanup, weak task lifetime")
    }

    private static func checkLetteringTaskLifetime() async throws {
        var temporary: AppState? = AppState()
        weak var released = temporary
        let previewURL = try unwrap(temporary?.letteringPreviewFile.url)
        try Data("preview".utf8).write(to: previewURL)
        temporary?.scheduleLetteringPreview()
        temporary = nil
        await Task.yield()
        check(released == nil, "A delayed lettering preview retained a closed app state.")
        check(!FileManager.default.fileExists(atPath: previewURL.path), "Closing an app state left its preview file behind.")
    }
}
