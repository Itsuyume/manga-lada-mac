import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension TranslationStateTests {
    static func checkBlankPageRecovery() async throws {
        let fixture = try Fixture(), state = fixture.state
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let book = try state.bookStore.prepare(sourceURL: unwrap(state.sourceURL), title: state.title,
            pages: state.pages, outputRoot: unwrap(state.outputRoot))
        try FileManager.default.createDirectory(at: book.pageURL(at: 0), withIntermediateDirectories: true)
        state.startTranslation(onlyCurrent: true)
        await state.job?.value
        check(state.pendingPages[0]?.translation.blocks.isEmpty == true && state.failures[0] != nil,
              "Blank-page write failure lost its recoverable draft.")
        try FileManager.default.removeItem(at: book.pageURL(at: 0))
        try state.updateCurrentTranslation(unwrap(state.currentReview))
        check(state.completed == [0] && state.pendingPages.isEmpty && state.failures.isEmpty, "Blank-page review did not recover.")
        check(try Data(contentsOf: book.pageURL(at: 0)) == fixture.sources[0].1, "Blank-page recovery changed image pixels.")
        try fixture.checkManifest(completed: [0], failures: [])
        try fixture.checkSources()
        print("PASS blank-page render failure and image-only recovery")
    }

    static func checkFailedPageReview() async throws {
        let first = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.7, height: 0.2), originalText: "今日は晴れ。", textKind: .dialogue)
        let second = TextBlock(box: TextBox(x: 0.1, y: 0.5, width: 0.7, height: 0.2), originalText: "…", textKind: .dialogue)
        let fixture = try Fixture(blocks: [first, second])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let state = fixture.state
        state.startTranslation(onlyCurrent: true)
        await state.job?.value
        check(state.failures[0] != nil && state.results.isEmpty, "Missing API key did not fail without a completed result.")
        check(state.currentReview?.blocks.map(\.originalText) == [first.originalText, second.originalText],
              "A translation failure hid successfully recognized text from the review editor.")
        let baseline = try unwrap(state.currentReview), book = try unwrap(state.outputBook)
        let recognitionURL = fixture.cache.cacheFileURL(fingerprint: fixture.keys[0].recognition)
        let recognitionBefore = try Data(contentsOf: recognitionURL)
        let cleanBefore = try Data(contentsOf: fixture.cleanURL(at: 0))
        check(state.completed.isEmpty && state.pendingPages.count == 1, "Recoverable OCR was counted as completed.")
        check(!FileManager.default.fileExists(atPath: book.pageURL(at: 0).path), "Failure created a finished image.")
        try fixture.checkManifest(completed: [], failures: [0])
        state.selectRegion(first.box)
        check(state.selectedRegionNumbers == [1] && state.isBlockSelected(first.id), "Failed-page region selection lost its number.")
        state.editReviewBlock(first.id) { $0.originalText = "明日は晴れ。" }
        let sourceEdit = try unwrap(state.currentReview)
        state.translatePendingWords()
        await state.job?.value
        check(state.errorMessage != nil && state.currentReview == sourceEdit, "Translation failure discarded edited OCR or hid its error.")
        state.errorMessage = nil
        state.translatePendingWords()
        state.stop()
        await state.job?.value
        check(state.currentReview == sourceEdit && state.errorMessage == nil, "Cancellation changed the review or showed an error.")
        state.editReviewBlock(first.id) { $0.translatedText = "내일은 맑아." }
        let partial = try unwrap(state.currentReview)
        try expectReviewRejection(state, translation: partial)
        check(state.currentReview == partial && state.results.isEmpty, "Rejected partial save changed the review.")
        check(!FileManager.default.fileExists(atPath: book.pageURL(at: 0).path), "Partial review rendered a blank translation.")
        check(try fixture.cache.load(fingerprint: baseline.imageFingerprint) == nil, "Typing or a rejected save populated the translation cache.")
        let restored = AppState(processor: MangaPageProcessor(applicationSupportDirectory: fixture.support),
            reviewStore: TranslationReviewStore(directory: fixture.support.appendingPathComponent("reviews")))
        restored.configuration = state.configuration; restored.pages = state.pages
        restored.sourceURL = state.sourceURL; restored.title = state.title; restored.outputRoot = state.outputRoot
        restored.startTranslation(onlyCurrent: true)
        await restored.job?.value
        check(restored.currentReview?.blocks == partial.blocks && restored.currentReview?.imageFingerprint == partial.imageFingerprint
              && restored.pendingPages.count == 1, "Reopening a failed page did not restore the persisted OCR edits.")
        state.translatePendingWords()
        await state.job?.value
        let filled = try unwrap(state.currentReview)
        check(filled.blocks[0] == partial.blocks[0] && filled.blocks[1].translatedText == "…", "Missing-only translation changed an existing review or failed punctuation.")
        check(filled.untranslatedBlockIDs.isEmpty && state.completed.isEmpty, "Filling a draft prematurely completed the page.")
        try checkReviewBoundaries(fixture, translation: filled)
        let cleanURL = fixture.cleanURL(at: 0), cleanBackup = cleanURL.appendingPathExtension("saved")
        try FileManager.default.moveItem(at: cleanURL, to: cleanBackup)
        try expectReviewRejection(state, translation: filled)
        check(state.currentReview == filled && state.completed.isEmpty && state.pendingPages.count == 1,
              "Rendering failure discarded a pending review.")
        check(!FileManager.default.fileExists(atPath: book.pageURL(at: 0).path), "Failed rendering created a finished image.")
        try FileManager.default.moveItem(at: cleanBackup, to: cleanURL)
        try checkReviewPersistenceFailure(fixture, translation: filled)
        state.failures[1] = "Keep unrelated failure"
        try state.updateCurrentTranslation(filled)
        let result = try unwrap(state.results[0])
        check(result.translation.blocks[0].userDefinedOriginalText == true, "Corrected OCR lost its provenance.")
        check(result.translation.blocks[1].userDefinedOriginalText == false, "Unchanged punctuation lost its original-image verification.")
        check(state.completed == [0] && state.pendingPages.isEmpty && state.failures == [1: "Keep unrelated failure"], "Successful review did not resolve only the corrected page.")
        check(state.reviewDrafts.isEmpty && !state.hasCurrentReview, "Applied draft was not cleared.")
        check(try state.reviewStore.load(for: baseline) == nil, "Applied review remained on disk.")
        check(try fixture.cache.load(fingerprint: baseline.imageFingerprint)?.blocks == result.translation.blocks, "Applied review did not reach the translation cache.")
        check(try !Data(contentsOf: result.renderedImageURL).isEmpty, "Completed review did not save an image.")
        check(try Data(contentsOf: recognitionURL) == recognitionBefore && Data(contentsOf: fixture.cleanURL(at: 0)) == cleanBefore, "Review changed OCR or the clean image.")
        try fixture.checkManifest(completed: [0], failures: [1])
        let savedImage = try Data(contentsOf: result.renderedImageURL)
        state.startTranslation(onlyCurrent: true, force: true)
        await state.job?.value
        check(state.failures[0] != nil && state.pendingPages.isEmpty && state.currentReview == result.translation,
              "Failed retranslation replaced an already saved review with unfinished OCR.")
        check(try Data(contentsOf: result.renderedImageURL) == savedImage, "Failed retranslation changed the saved review image.")
        try fixture.checkSources()
        print("PASS failed-page OCR, region selection, edit persistence, missing-only translation, cancellation and completion")
    }

    private static func checkReviewBoundaries(_ fixture: Fixture, translation: PageTranslation) throws {
        let state = fixture.state
        var foreign = translation
        foreign.imageFingerprint += "-wrong-page"
        try expectReviewRejection(state, translation: foreign)
        foreign = translation; foreign.blocks.removeLast()
        try expectReviewRejection(state, translation: foreign)
        foreign = translation; foreign.blocks.append(translation.blocks[0])
        try expectReviewRejection(state, translation: foreign)
        foreign = translation; foreign.blocks[0].translatedText = " \n\t"
        try expectReviewRejection(state, translation: foreign)
        check(state.currentReview == translation && state.pendingPages.count == 1 && state.results.isEmpty,
              "An invalid page/region/blank review changed state.")
        print("PASS foreign page, missing/duplicate regions and whitespace rejection")
    }

    private static func checkReviewPersistenceFailure(_ fixture: Fixture, translation: PageTranslation) throws {
        let state = fixture.state, book = try unwrap(state.outputBook)
        let manifestURL = book.directory.appendingPathComponent(ImageFileScanner.generatedBookMarker)
        let manifestBefore = try Data(contentsOf: manifestURL)
        try FileManager.default.removeItem(at: manifestURL)
        try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: false)
        try expectReviewRejection(state, translation: translation)
        check(state.results.isEmpty && state.completed.isEmpty && state.failures[0] != nil,
              "Failed manifest write was reported as complete.")
        check(state.currentReview == translation && state.pendingPages.count == 1 && state.hasCurrentReview,
              "Failed manifest write lost the recoverable draft.")
        check(try state.reviewStore.load(for: unwrap(state.currentReviewBaseline)) == translation,
              "Failed manifest write discarded the review on disk.")
        try FileManager.default.removeItem(at: manifestURL)
        try manifestBefore.write(to: manifestURL, options: .atomic)
        print("PASS save failure keeps incomplete status and persisted edits")
    }

    private static func expectReviewRejection(_ state: AppState, translation: PageTranslation) throws {
        do { try state.updateCurrentTranslation(translation) }
        catch { return }
        fatalError("An incomplete, foreign, or unsavable review was accepted.")
    }
}
