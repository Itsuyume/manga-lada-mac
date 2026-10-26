import Foundation
import MangaLadaCore

extension TranslationStateTests {
    static func checkReviewTextBinding() async throws {
        let block = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.3),
                              originalText: "金で本を買った。", textKind: .dialogue)
        let fixture = try Fixture(blocks: [block]), state = fixture.state
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        state.startTranslation(onlyCurrent: true)
        await state.job?.value
        state.editReviewBlock(block.id) { $0.translatedText = "금으로 책을 샀어." }
        try state.updateCurrentTranslation(unwrap(state.currentReview))
        let baseline = try unwrap(state.currentReview), savedBlock = try unwrap(baseline.blocks.first)
        let image = try unwrap(state.currentResult?.renderedImageURL), before = try Data(contentsOf: image)
        let inspector = TranslationInspector(state: state)
        let binding = inspector.textBinding(savedBlock, \.translatedText)

        // Reuse the same binding: TextEditor can read it again before SwiftUI rebuilds the row.
        binding.wrappedValue = "돈으로 책을 샀어."
        check(binding.wrappedValue == "돈으로 책을 샀어.", "Text binding returned a stale value immediately after typing.")
        binding.wrappedValue = "돈으로\n책을 샀어."
        check(binding.wrappedValue == "돈으로\n책을 샀어.", "Rapid edits or explicit line breaks were lost.")
        check(try state.reviewStore.load(for: baseline) == state.currentReview, "Typed text was not persisted as a review.")
        check(try Data(contentsOf: image) == before, "Typing changed the completed image before Apply.")
        check(state.currentReview?.blocks.first?.originalText == block.originalText, "Translation editing changed the OCR source.")

        binding.wrappedValue = ""
        check(binding.wrappedValue.isEmpty && state.currentReview?.untranslatedBlockIDs == [block.id], "Deleting text did not keep a recoverable empty draft.")
        binding.wrappedValue = savedBlock.translatedText
        check(!state.hasCurrentReview && binding.wrappedValue == savedBlock.translatedText, "Reverting to the baseline left stale editor state.")
        binding.wrappedValue = "돈으로 책을 샀어."
        try state.updateCurrentTranslation(unwrap(state.currentReview))
        check(!state.hasCurrentReview && binding.wrappedValue == "돈으로 책을 샀어.", "Apply lost the latest editor value.")
        check(try Data(contentsOf: image) != before, "Apply did not update rendered text.")

        // A delayed callback from a removed row must not edit a newly selected page/session.
        state.results[1] = state.results[0]
        state.select(1)
        let other = state.currentReview
        binding.wrappedValue = "別のページ"
        check(state.currentReview == other && !state.hasCurrentReview, "A stale text binding edited another page.")
        state.select(0); state.sessionID = UUID()
        let reopened = state.currentReview
        binding.wrappedValue = "別のセッション"
        check(state.currentReview == reopened && !state.hasCurrentReview, "A stale text binding edited a reopened document.")
        try fixture.checkSources()
        print("PASS review binding immediate reads, rapid/empty edits, persistence, Apply, page/session and source preservation")
    }
}
