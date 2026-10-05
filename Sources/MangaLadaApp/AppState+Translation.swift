import Foundation
import MangaLadaCore
import MangaLadaWorkflow

extension AppState {
    func startTranslation(onlyCurrent: Bool = false, force: Bool = false) {
        guard !isBusy, !isLoading, !pages.isEmpty else { return }
        let requested = onlyCurrent ? [currentIndex] : Array(pages.indices)
        let indices = requested.filter { force || results[$0] == nil || failures[$0] != nil }
        guard !indices.isEmpty, requireAppliedReviews(at: indices) else { return }
        if outputRoot == nil {
            chooseOutputFolder { [weak self] in self?.startTranslation(onlyCurrent: onlyCurrent, force: force) }
            return
        }
        guard let outputRoot, let sourceURL else { statusMessage = "완성본 저장 폴더를 먼저 지정해주세요."; return }
        do { outputBook = try bookStore.prepare(sourceURL: sourceURL, title: title, pages: pages, outputRoot: outputRoot) }
        catch { errorMessage = error.localizedDescription; return }
        let id = sessionID; isBusy = true
        job = Task { await translate(indices: indices, force: force, session: id) }
    }
    private func translate(indices: [Int], force: Bool, session: UUID) async {
        defer { if sessionID == session { isBusy = false; processingIndex = nil; job = nil } }
        do {
            statusMessage = "로컬 일본어·효과음 인식 모델 확인 중…"
            if configuration.enhanceSoundEffects { try await runtime.ensureReady(model: OllamaConfiguration.visionModel) }
            if configuration.provider == .ollama { statusMessage = "로컬 모델 확인 중…"; try await runtime.ensureReady(model: configuration.ollama.model) }
            for index in indices {
                try Task.checkCancellation(); guard sessionID == session else { return }
                let retrySavedPage = results[index] != nil && failures[index] != nil
                try await translatePage(at: index, force: force || retrySavedPage, session: session)
            }
            let warnings = results.values.filter { !$0.reviewWarnings.isEmpty || $0.translation.blocks.contains { $0.maskedTextInterpretation != nil } }.count
            statusMessage = failures.isEmpty ? "번역 저장 완료 · \(completed.count)/\(pages.count)페이지" : "처리 완료 · 성공 \(completed.count) · 실패 \(failures.count)"
            if warnings > 0 { statusMessage += " · 검수 안내 \(warnings)페이지" }
        } catch is CancellationError { if sessionID == session { statusMessage = "중단됨 · 완성한 \(results.count)페이지는 저장되어 있습니다." } }
        catch { if sessionID == session { statusMessage = "번역을 시작하지 못했습니다."; errorMessage = error.localizedDescription } }
    }
    private func translatePage(at index: Int, force: Bool, session: UUID) async throws {
        guard let book = outputBook else { return }; processingIndex = index
        let previous = results[index - 1]?.translation.blocks.map { "\($0.originalText): \($0.translatedText)" }.joined(separator: "\n") ?? ""
        do {
            let result = try await processor.process(imageURL: pages[index].url, destinationURL: book.pageURL(at: index),
                                                     configuration: configuration, typography: typography, previousContext: previous, bookTitle: title, force: force) { [weak self] message in
                await self?.updateStatus(message, page: index, session: session)
            }
            guard sessionID == session else { return }
            recordResult(result, at: index); failures.removeValue(forKey: index); imageRevision += 1
            if var updated = outputBook {
                updated.manifest.completedPages = completed.sorted(); updated.manifest.failures = failures
                try bookStore.save(updated); outputBook = updated
            }
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            guard sessionID == session else { return }
            if let failure = error as? MangaPageFailure { recordPending(failure.draft, at: index) }
            failures[index] = error.localizedDescription
            if var updated = outputBook {
                updated.manifest.completedPages = completed.sorted(); updated.manifest.failures = failures
                try bookStore.save(updated); outputBook = updated
            }
        }
    }
    private func updateStatus(_ message: String, page: Int, session: UUID) {
        guard sessionID == session else { return }; statusMessage = "\(page + 1)/\(pages.count) · \(message)"
    }
    func updateCurrentTranslation(_ translation: PageTranslation) throws {
        guard !isBusy else { return }
        let edited: ProcessedMangaPage
        if let result = currentResult {
            edited = try processor.applyEdits(to: result, translation: translation, typography: typography)
        } else if let draft = pendingPages[currentIndex], let book = outputBook {
            edited = try processor.finishReview(of: draft, translation: translation, destinationURL: book.pageURL(at: currentIndex), typography: typography)
        } else { return }
        try finishReview(edited, at: currentIndex)
        statusMessage = "문구와 글꼴 수정을 이미지에 저장했습니다."
    }
}
