import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension AppState {
    var selectedRegionNumbers: [Int] {
        guard let selectedRegion, let blocks = currentResult?.translation.blocks else { return [] }
        return blocks.indices.filter { ImageRegionSelection.containsCenter(selectedRegion, of: blocks[$0].box) }.map { $0 + 1 }
    }
    func isBlockSelected(_ id: UUID) -> Bool {
        guard id != selectedBlockID else { return true }
        guard let selectedRegion, let block = currentResult?.translation.blocks.first(where: { $0.id == id }) else { return false }
        return ImageRegionSelection.containsCenter(selectedRegion, of: block.box)
    }
    func focusBlock(_ id: UUID?) {
        selectedBlockID = id; blockFocusRevision += 1
    }
    func selectRegion(_ box: TextBox?) {
        selectedRegion = box
        guard let box else { focusBlock(nil); return }
        let match = currentResult?.translation.blocks.first { ImageRegionSelection.containsCenter(box, of: $0.box) }
        if selectedBlockID != match?.id { focusBlock(match?.id) }
    }
    func retranslateBlock(in translation: PageTranslation, at blockIndex: Int) {
        guard !isBusy, !isLoading, let result = currentResult, translation.blocks.indices.contains(blockIndex) else { return }
        let page = currentIndex, id = sessionID
        isBusy = true
        job = Task { [self] in
            defer { if sessionID == id { isBusy = false; job = nil } }
            do {
                if configuration.provider == .ollama { try await runtime.ensureReady(model: configuration.ollama.model) }
                statusMessage = "페이지 문맥을 참고해 선택한 문구를 다시 번역하는 중…"
                var updated = translation
                updated.blocks = try await TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean)
                    .translateSelected([translation.blocks[blockIndex].id], in: translation.blocks, configuration: configuration)
                try Task.checkCancellation()
                guard sessionID == id else { return }
                results[page] = try processor.applyEdits(to: result, translation: updated, typography: typography)
                imageRevision += 1; statusMessage = "이 문구를 다시 번역해 저장했습니다."
            } catch is CancellationError { statusMessage = "문구 번역을 중단했습니다." }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func translateSelectedRegion() {
        guard !isBusy, !isLoading, let box = selectedRegion, pages.indices.contains(currentIndex) else { return }
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
                results[index] = result; failures.removeValue(forKey: index); imageRevision += 1
                isSelectingRegion = false; selectedRegion = nil; mode = .translated
                focusBlock(result.translation.blocks.first { ImageRegionSelection.containsCenter(box, of: $0.box) }?.id)
                if var updated = outputBook {
                    updated.manifest.completedPages = results.keys.sorted(); updated.manifest.failures = failures
                    try bookStore.save(updated); outputBook = updated
                }
                statusMessage = "지정한 영역을 번역하고 페이지를 저장했습니다."
            } catch is CancellationError { statusMessage = "영역 번역을 중단했습니다. 기존 결과는 유지됩니다." }
            catch { errorMessage = error.localizedDescription; statusMessage = "지정 영역 처리 실패 · 영역을 조절해주세요." }
        }
    }
}
