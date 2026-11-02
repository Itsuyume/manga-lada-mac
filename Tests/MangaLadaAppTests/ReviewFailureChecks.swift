import Foundation
import MangaLadaCore

extension TranslationStateTests {
    static func checkReviewFailurePreservation() async throws {
        try await checkDraftWriteFailure()
        try await checkApplyWriteFailure()
    }

    private static func savedReviewFixture() async throws -> Fixture {
        let block = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.8, height: 0.3), originalText: "今日は晴れ。",
                              translatedText: "오늘은 맑아.", textKind: .dialogue)
        let fixture = try Fixture(blocks: [block]), state = fixture.state
        try fixture.cache.save(PageTranslation(imageURL: fixture.sources[0].0, imageFingerprint: fixture.keys[0].translation,
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: [block]))
        state.startTranslation(onlyCurrent: true); await state.job?.value
        _ = try unwrap(state.currentResult)
        return fixture
    }

    private static func checkDraftWriteFailure() async throws {
        let fixture = try await savedReviewFixture(), state = fixture.state
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let baseline = try unwrap(state.currentReview), block = try unwrap(baseline.blocks.first)
        state.editReviewBlock(block.id) { $0.translatedText = "첫 번째 수정." }
        let folder = fixture.support.appendingPathComponent("reviews"), backup = fixture.support.appendingPathComponent("reviews-backup")
        try FileManager.default.moveItem(at: folder, to: backup)
        try Data("unwritable directory".utf8).write(to: folder)
        state.editReviewBlock(block.id) { $0.translatedText = "저장 실패 중 입력한 수정." }
        check(state.currentReview?.blocks.first?.translatedText == "저장 실패 중 입력한 수정.", "A draft write failure discarded the user's latest typing.")
        check(state.hasCurrentReview && state.errorMessage != nil, "A draft write failure was hidden or stopped protecting edits.")
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.moveItem(at: backup, to: folder)
        state.editReviewBlock(block.id) { $0.translatedText += " 다시 저장." }
        check(try state.reviewStore.load(for: baseline) == state.currentReview, "A recovered storage path did not save the retained edit.")
        try fixture.checkSources()
        print("PASS draft write failure retains latest typing and supports retry")
    }

    private static func checkApplyWriteFailure() async throws {
        let fixture = try await savedReviewFixture(), state = fixture.state
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let baseline = try unwrap(state.currentReview), block = try unwrap(baseline.blocks.first)
        let image = try unwrap(state.currentResult?.renderedImageURL), before = try Data(contentsOf: image)
        let cacheURL = fixture.cache.cacheFileURL(fingerprint: baseline.imageFingerprint), cacheBefore = try Data(contentsOf: cacheURL)
        let book = try unwrap(state.outputBook), marker = book.directory.appendingPathComponent(ImageFileScanner.generatedBookMarker)
        let markerBefore = try Data(contentsOf: marker)
        state.editReviewBlock(block.id) { $0.translatedText = "내일은 비가 와." }
        let draft = try unwrap(state.currentReview)
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        do { try state.updateCurrentTranslation(draft); fatalError("Failed book persistence was accepted.") }
        catch { }
        check(try Data(contentsOf: image) == before, "A failed Apply replaced the previously saved image.")
        check(try Data(contentsOf: cacheURL) == cacheBefore, "A failed Apply replaced the previously saved translation cache.")
        check(state.currentResult?.translation == baseline && state.currentReview == draft && state.hasCurrentReview,
              "A failed Apply changed committed state or lost the pending review.")
        check(try state.reviewStore.load(for: baseline) == draft, "A failed Apply deleted the recoverable review file.")
        try FileManager.default.removeItem(at: marker)
        try markerBefore.write(to: marker, options: .atomic)
        try state.updateCurrentTranslation(draft)
        check(!state.hasCurrentReview && state.currentResult?.translation.blocks.first?.translatedText == "내일은 비가 와.",
              "Apply did not recover after restoring storage.")
        try fixture.checkSources()
        print("PASS failed Apply rolls back saved image/cache, retains draft and supports retry")
    }
}
