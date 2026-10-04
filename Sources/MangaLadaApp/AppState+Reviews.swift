import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension AppState {
    var currentReview: PageTranslation? { reviewDrafts[currentIndex] ?? currentResult?.translation }
    var hasCurrentReview: Bool { reviewDrafts[currentIndex] != nil || reviewErrors[currentIndex] != nil }

    func editReviewBlock(_ id: UUID, change: (inout TextBlock) -> Void) {
        guard !isBusy, !isLoading, reviewErrors[currentIndex] == nil,
              let saved = currentResult?.translation, var edited = currentReview else { return }
        guard let index = edited.blocks.firstIndex(where: { $0.id == id }) else {
            errorMessage = "편집할 문구가 바뀌었습니다. 현재 페이지의 문구를 다시 선택해주세요."; return
        }
        change(&edited.blocks[index])
        do {
            try reviewStore.save(edited, comparedTo: saved)
            reviewDrafts[currentIndex] = edited == saved ? nil : edited
        } catch { errorMessage = "임시 수정을 저장하지 못했습니다. \(error.localizedDescription)" }
    }

    func discardCurrentReview() {
        guard !isBusy, let saved = currentResult?.translation else { return }
        do {
            try reviewStore.discard(fingerprint: saved.imageFingerprint)
            reviewDrafts.removeValue(forKey: currentIndex); reviewErrors.removeValue(forKey: currentIndex)
            statusMessage = "이 페이지의 임시 수정을 취소했습니다. 저장된 이미지와 번역은 유지됩니다."
        } catch { errorMessage = error.localizedDescription }
    }

    func recordResult(_ result: ProcessedMangaPage, at index: Int) {
        results[index] = result
        do {
            reviewDrafts[index] = try reviewStore.load(for: result.translation)
            reviewErrors.removeValue(forKey: index)
        } catch {
            reviewDrafts.removeValue(forKey: index)
            reviewErrors[index] = "임시 수정을 읽지 못했습니다. 파일은 보존했습니다. \(error.localizedDescription)"
        }
    }

    func finishReview(_ result: ProcessedMangaPage, at index: Int) throws {
        results[index] = result; imageRevision += 1
        try reviewStore.discard(fingerprint: result.translation.imageFingerprint)
        reviewDrafts.removeValue(forKey: index); reviewErrors.removeValue(forKey: index)
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
