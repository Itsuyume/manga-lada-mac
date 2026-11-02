import AppKit
import MangaLadaCore

extension AppState {
    var bookConfiguration: LocalTranslatorConfiguration {
        var request = configuration
        request.terminology = bookTerminology
        return request
    }
    func reloadBookTerminology() {
        guard !isBusy, !isLoading, let sourceURL else { return }
        loadBookTerminology(for: sourceURL)
    }
    func loadBookTerminology(for source: URL) {
        do { bookTerminology = try terminologyStore.load(for: source); terminologyReadError = nil }
        catch {
            bookTerminology = TranslationGlossary()
            terminologyReadError = "책 용어집을 읽지 못했습니다. 기존 파일은 보존했습니다. \(error.localizedDescription)"
        }
    }
    func requireBookTerminology() -> Bool {
        guard let failure = terminologyReadError else { return true }
        showInspector = true; errorMessage = failure
        return false
    }
    @discardableResult
    func setBookTerm(source: String, korean: String) -> Bool {
        guard !isBusy, !isLoading, let sourceURL, requireBookTerminology() else { return false }
        do {
            let updated = try bookTerminology.setting(source: source, korean: korean)
            try terminologyStore.save(updated, for: sourceURL)
            bookTerminology = updated
            statusMessage = "책 용어를 저장했습니다. 새 번역과 문구 재번역부터 사용합니다."
            return true
        } catch { errorMessage = "책 용어를 저장하지 못했습니다. \(error.localizedDescription)"; return false }
    }
    func removeBookTerm(source: String) {
        guard !isBusy, !isLoading, let sourceURL, requireBookTerminology() else { return }
        do {
            let updated = try bookTerminology.removing(source: source)
            try terminologyStore.save(updated, for: sourceURL)
            bookTerminology = updated
            statusMessage = "책 용어를 삭제했습니다. 기존 번역과 이미지는 유지됩니다."
        } catch { errorMessage = "책 용어를 삭제하지 못했습니다. \(error.localizedDescription)" }
    }
    func revealBookTerminology() {
        guard let sourceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([terminologyStore.fileURL(for: sourceURL)])
    }
}
