import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension AppState {
    var currentReviewBaseline: PageTranslation? { currentResult?.translation ?? pendingPages[currentIndex]?.translation }
    var currentReview: PageTranslation? { reviewDrafts[currentIndex] ?? currentReviewBaseline }
    var hasCurrentReview: Bool { reviewDrafts[currentIndex] != nil || reviewErrors[currentIndex] != nil }

    func applyDictionaryEffect(_ id: UUID) {
        guard let block = currentReview?.blocks.first(where: { $0.id == id }),
              let korean = effectLexicon?.translation(for: block.originalText) else {
            errorMessage = "현재 문구에 적용할 효과음 사전 표기가 없습니다."; return
        }
        editReviewBlock(id) {
            $0.translatedText = korean; $0.textKind = .soundEffect; $0.userDefinedTextKind = true
        }
    }

    func editReviewBlock(_ id: UUID, change: (inout TextBlock) -> Void) {
        guard !isBusy, !isLoading, reviewErrors[currentIndex] == nil,
              let saved = currentReviewBaseline, var edited = currentReview else { return }
        guard let index = edited.blocks.firstIndex(where: { $0.id == id }) else {
            errorMessage = "편집할 문구가 바뀌었습니다. 현재 페이지의 문구를 다시 선택해주세요."; return
        }
        change(&edited.blocks[index])
        do {
            try saveReview(edited, comparedTo: saved, at: currentIndex)
        } catch { errorMessage = "임시 수정을 저장하지 못했습니다. \(error.localizedDescription)" }
    }

    func saveReview(_ edited: PageTranslation, comparedTo saved: PageTranslation, at index: Int) throws {
        try reviewStore.save(edited, comparedTo: saved)
        reviewDrafts[index] = edited == saved ? nil : edited
    }

    func discardCurrentReview() {
        guard !isBusy, let saved = currentReviewBaseline else { return }
        do {
            try reviewStore.discard(fingerprint: saved.imageFingerprint)
            reviewDrafts.removeValue(forKey: currentIndex); reviewErrors.removeValue(forKey: currentIndex)
            clearLetteringPreview()
            statusMessage = "이 페이지의 임시 수정을 취소했습니다. 저장된 이미지와 번역은 유지됩니다."
        } catch { errorMessage = error.localizedDescription }
    }

    func recordResult(_ result: ProcessedMangaPage, at index: Int) {
        results[index] = result; pendingPages.removeValue(forKey: index)
        restoreReview(for: result.translation, at: index)
    }

    func recordPending(_ draft: MangaPageDraft, at index: Int) {
        // A failed retranslation must keep the last saved image and its review baseline.
        guard results[index] == nil else { return }
        pendingPages[index] = draft
        restoreReview(for: draft.translation, at: index)
    }

    private func restoreReview(for translation: PageTranslation, at index: Int) {
        do {
            reviewDrafts[index] = try reviewStore.load(for: translation)
            reviewErrors.removeValue(forKey: index)
        } catch {
            reviewDrafts.removeValue(forKey: index)
            reviewErrors[index] = "임시 수정을 읽지 못했습니다. 파일은 보존했습니다. \(error.localizedDescription)"
        }
    }

    func finishReview(_ result: ProcessedMangaPage, at index: Int) throws {
        var remainingFailures = failures
        remainingFailures.removeValue(forKey: index)
        if var updated = outputBook {
            updated.manifest.completedPages = Set(results.keys).union([index]).subtracting(remainingFailures.keys).sorted()
            updated.manifest.failures = remainingFailures
            try bookStore.save(updated); outputBook = updated
        }
        results[index] = result; failures = remainingFailures; imageRevision += 1
        pendingPages.removeValue(forKey: index)
        try reviewStore.discard(fingerprint: result.translation.imageFingerprint)
        reviewDrafts.removeValue(forKey: index); reviewErrors.removeValue(forKey: index)
        if index == currentIndex { clearLetteringPreview() }
    }

    func requireAppliedReviews(at indices: [Int]? = nil) -> Bool {
        let pending = Set(reviewDrafts.keys).union(reviewErrors.keys)
        let relevant = indices.map { pending.intersection($0) } ?? pending
        guard let first = relevant.min() else { return true }
        showInspector = true; select(first)
        errorMessage = "\(relevant.sorted().map { String($0 + 1) }.joined(separator: ", "))쪽에 적용하지 않은 수정이 있습니다. 검수창에서 ‘수정 적용’ 또는 ‘수정 취소’를 먼저 눌러주세요."
        return false
    }
}
