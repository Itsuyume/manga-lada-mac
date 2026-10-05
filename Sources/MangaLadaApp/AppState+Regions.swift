import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension AppState {
    var selectedRegionNumbers: [Int] {
        guard let selectedRegion, let blocks = currentReview?.blocks else { return [] }
        if let placementBlockID { return blocks.indices.filter { blocks[$0].id == placementBlockID }.map { $0 + 1 } }
        return blocks.indices.filter { ImageRegionSelection.containsCenter(selectedRegion, of: blocks[$0].box) }.map { $0 + 1 }
    }
    func isBlockSelected(_ id: UUID) -> Bool {
        guard id != selectedBlockID else { return true }
        guard let selectedRegion, let block = currentReview?.blocks.first(where: { $0.id == id }) else { return false }
        return ImageRegionSelection.containsCenter(selectedRegion, of: block.box)
    }
    func focusBlock(_ id: UUID?) {
        selectedBlockID = id; blockFocusRevision += 1
    }
    func selectRegion(_ box: TextBox?) {
        selectedRegion = box
        if let placementBlockID { focusBlock(placementBlockID); return }
        guard let box else { focusBlock(nil); return }
        let match = currentReview?.blocks.first { ImageRegionSelection.containsCenter(box, of: $0.box) }
        if selectedBlockID != match?.id { focusBlock(match?.id) }
    }
    func retranslateBlock(in translation: PageTranslation, at blockIndex: Int) {
        guard translation.blocks.indices.contains(blockIndex) else { return }
        let block = translation.blocks[blockIndex]
        retranslateBlocks([block.id], in: translation, interpretMasks: MaskedTextTranslation.requiresContextTranslation(block.originalText))
    }
    func retranslateMaskedWords() {
        guard let translation = currentReview else { return }
        retranslateBlocks(translation.maskedTextReviewIDs, in: translation, interpretMasks: true)
    }
    func translatePendingWords() {
        guard pendingPages[currentIndex] != nil, let translation = currentReview else { return }
        retranslateBlocks(translation.untranslatedBlockIDs, in: translation)
    }
    private func retranslateBlocks(_ selectedIDs: Set<UUID>, in translation: PageTranslation, interpretMasks: Bool = false) {
        let selectedIDs = selectedIDs.subtracting(translation.blocks.filter { $0.preservesOriginalArtwork }.map(\.id))
        guard !isBusy, !isLoading, !selectedIDs.isEmpty, let baseline = currentReviewBaseline else { return }
        guard reviewErrors[currentIndex] == nil else { _ = requireAppliedReviews(at: [currentIndex]); return }
        let page = currentIndex, id = sessionID
        var requestConfiguration = configuration
        if interpretMasks { requestConfiguration.interpretMaskedText = true }
        let configuration = requestConfiguration
        let onlyMasked = configuration.interpretMaskedText && translation.blocks.filter { selectedIDs.contains($0.id) }
            .allSatisfy { MaskedTextTranslation.requiresContextTranslation($0.originalText) }
        isBusy = true
        job = Task { [self] in
            defer { if sessionID == id { isBusy = false; job = nil } }
            do {
                if onlyMasked || configuration.provider == .ollama {
                    try await runtime.ensureReady(model: onlyMasked ? OllamaConfiguration.visionModel : configuration.ollama.model)
                }
                statusMessage = onlyMasked ? "이전 해석 캐시를 건너뛰고 Qwen으로 선택 문구를 판단하는 중…"
                    : "페이지 문맥을 참고해 선택한 문구를 다시 번역하는 중…"
                var updated = translation
                updated.blocks = try await processor.textTranslator.translateSelected(
                    selectedIDs, in: translation.blocks, configuration: configuration, refreshMaskedContext: true)
                try Task.checkCancellation()
                guard sessionID == id else { return }
                try saveReview(updated, comparedTo: baseline, at: page)
                statusMessage = "\(page + 1)쪽 문구를 다시 번역했습니다. ‘수정 적용’을 눌러 이미지에 저장하세요."
            } catch {
                guard sessionID == id else { return }
                if Task.isCancelled || error is CancellationError { statusMessage = "문구 번역을 중단했습니다." }
                else { errorMessage = error.localizedDescription }
            }
        }
    }
    func translateSelectedRegion() {
        guard placementBlockID == nil, !isBusy, !isLoading, let box = selectedRegion, pages.indices.contains(currentIndex),
              requireAppliedReviews(at: [currentIndex]) else { return }
        if outputRoot == nil { chooseOutputFolder { [weak self] in self?.translateSelectedRegion() }; return }
        guard let outputRoot, let sourceURL else { return }
        do { outputBook = try bookStore.prepare(sourceURL: sourceURL, title: title, pages: pages, outputRoot: outputRoot) }
        catch { errorMessage = error.localizedDescription; return }
        let index = currentIndex, id = sessionID
        let kind = selectedRegionKind
        isBusy = true; processingIndex = index
        job = Task { [self] in
            defer { if sessionID == id { isBusy = false; processingIndex = nil; job = nil } }
            do {
                if configuration.provider == .ollama { try await runtime.ensureReady(model: configuration.ollama.model) }
                guard let book = outputBook else { return }
                let result = try await processor.translateRegion(imageURL: pages[index].url, destinationURL: book.pageURL(at: index),
                    box: box, kind: kind, configuration: configuration, typography: typography, bookTitle: title) { [weak self] message in
                    await MainActor.run { if self?.sessionID == id { self?.statusMessage = message } }
                }
                guard sessionID == id else { return }
                recordResult(result, at: index); failures.removeValue(forKey: index); imageRevision += 1
                isSelectingRegion = false; selectedRegion = nil; mode = .translated
                focusBlock(result.translation.blocks.first { ImageRegionSelection.containsCenter(box, of: $0.box) }?.id)
                if var updated = outputBook {
                    updated.manifest.completedPages = completed.sorted(); updated.manifest.failures = failures
                    try bookStore.save(updated); outputBook = updated
                }
                statusMessage = "지정한 영역을 번역하고 페이지를 저장했습니다."
            } catch is CancellationError { statusMessage = "영역 번역을 중단했습니다. 기존 결과는 유지됩니다." }
            catch { errorMessage = error.localizedDescription; statusMessage = "지정 영역 처리 실패 · 영역을 조절해주세요." }
        }
    }
}
