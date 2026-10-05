import Foundation
import MangaLadaCore
import MangaLadaRendering

extension AppState {
    func beginLetteringPlacement(_ id: UUID) {
        guard !isBusy, !isLoading, reviewErrors[currentIndex] == nil,
              let block = currentReview?.blocks.first(where: { $0.id == id }) else { return }
        placementBlockID = id; isSelectingRegion = true; showInspector = true
        selectedRegion = LetteringPreferences.layoutBounds(for: block)
        focusBlock(id)
    }

    func stageLetteringPlacement() {
        guard !isBusy, !isLoading, let id = placementBlockID, let selectedRegion,
              let saved = currentReviewBaseline, var draft = currentReview,
              let index = draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        draft.blocks[index].textLayoutBounds = selectedRegion
        draft.blocks[index].textOffset = nil
        do {
            try saveReview(draft, comparedTo: saved, at: currentIndex)
            placementBlockID = nil; isSelectingRegion = false; self.selectedRegion = nil
            mode = .translated
            scheduleLetteringPreview()
            statusMessage = "배치 영역을 임시 보관했습니다. ‘수정 적용’을 누르면 번역 없이 이미지만 다시 저장합니다."
        } catch { errorMessage = error.localizedDescription }
    }

    func moveLettering(_ id: UUID, by delta: CGSize) {
        guard !isBusy, !isLoading, reviewErrors[currentIndex] == nil,
              let saved = currentReviewBaseline, var draft = currentReview,
              let index = draft.blocks.firstIndex(where: { $0.id == id }) else { return }
        do {
            draft.blocks[index] = try LetteringPreferences.moved(draft.blocks[index], by: .init(x: delta.width, y: delta.height))
            try saveReview(draft, comparedTo: saved, at: currentIndex)
            focusBlock(id); scheduleLetteringPreview()
        } catch { errorMessage = error.localizedDescription }
    }

    func scheduleLetteringPreview() {
        letteringPreviewTask?.cancel()
        let page = currentIndex, session = sessionID
        letteringPreviewTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) }
            catch is CancellationError { return }
            catch { self?.letteringPreviewError = error.localizedDescription; return }
            guard let self, currentIndex == page, sessionID == session, !isBusy,
                  let cleanURL = currentResult?.cleanImageURL ?? pendingPages[page]?.cleanImageURL,
                  let review = currentReview else { return }
            let url = letteringPreviewFile.url
            do {
                try autoreleasepool {
                    _ = try TranslatedImageRenderer(typography: typography).writePNG(sourceImageURL: cleanURL,
                        translation: review, destinationURL: url, fontScale: typography.fontScale,
                        backgroundStyle: .none, originalImageURL: review.imageURL)
                }
                letteringPreviewURL = url; letteringPreviewError = nil; imageRevision += 1
            } catch { letteringPreviewError = error.localizedDescription }
            letteringPreviewTask = nil
        }
    }

    func clearLetteringPreview() {
        letteringPreviewTask?.cancel(); letteringPreviewTask = nil
        if let letteringPreviewURL { try? FileManager.default.removeItem(at: letteringPreviewURL) }
        letteringPreviewURL = nil; letteringPreviewError = nil
    }
}
