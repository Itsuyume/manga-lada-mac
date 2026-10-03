import AppKit
import MangaLadaCore
import MangaLadaImport
import MangaLadaViewerUI
import MangaLadaWorkflow
import UniformTypeIdentifiers

extension AppState {
    func chooseBook(folderOnly: Bool = false) {
        guard !isShowingFilePanel else { return }; isShowingFilePanel = true
        Task {
            defer { isShowingFilePanel = false }
            guard let url = await ComicOpenPanel.choose(folderOnly: folderOnly) else { return }
            await open(url)
        }
    }
    func open(_ url: URL) async {
        await open(.file(url))
    }
    func open(_ input: ComicInput) async {
        let id = UUID(); sessionID = id
        job?.cancel(); await job?.value
        guard sessionID == id else { return }
        isBusy = false; job = nil; processingIndex = nil
        isLoading = true; statusMessage = "페이지를 여는 중…"
        do {
            let book = try await loader.load(input)
            guard sessionID == id else { return }
            pages = book.pages; currentIndex = book.initialIndex; title = book.title; sourceURL = book.sourceURL
            isSelectingRegion = false; selectedRegion = nil; selectedBlockID = nil
            results = [:]; failures = [:]; outputBook = nil; imageRevision += 1; isLoading = false
            statusMessage = "\(pages.count)페이지를 열었습니다."
            if autoTranslate { startTranslation() }
        } catch { if sessionID == id { isLoading = false; statusMessage = "열기 실패"; errorMessage = error.localizedDescription } }
    }
    func chooseOutputFolder(then completion: @escaping @MainActor () -> Void = {}) {
        guard !isBusy, !isShowingFilePanel else { return }; isShowingFilePanel = true
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "완성본 저장 위치 지정"; panel.title = "번역된 만화를 저장할 폴더"
        panel.message = "이 폴더 아래에 책별 ‘한국어’ 폴더를 만들고 번역된 페이지를 자동 저장합니다."
        panel.directoryURL = outputRoot
        Task {
            let response = await ComicOpenPanel.present(panel); isShowingFilePanel = false
            guard response == .OK, let url = panel.url else { return }
            applyOutputFolder(url); completion()
        }
    }
    private func applyOutputFolder(_ url: URL) {
        if outputRoot != url { results = [:]; failures = [:]; imageRevision += 1 }
        outputRoot = url; outputBook = nil; UserDefaults.standard.set(url.path, forKey: "translator.outputRoot")
        statusMessage = "완성본 저장 위치: \(url.lastPathComponent)"
    }
    func revealOutput() {
        guard let url = outputBook?.directory ?? outputRoot else { chooseOutputFolder(); return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    func openInReader() {
        guard let directory = outputBook?.directory, !results.isEmpty else { return }
        Task {
            do { try await CompanionApplication.reader.open(directory) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func exportCurrentPNG() {
        guard let result = currentResult, !isShowingFilePanel else { return }; isShowingFilePanel = true
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.directoryURL = outputBook?.directory
        panel.nameFieldStringValue = result.renderedImageURL.lastPathComponent
        Task {
            defer { isShowingFilePanel = false }
            guard await ComicOpenPanel.present(panel) == .OK, let target = panel.url else { return }
            do { try Data(contentsOf: result.renderedImageURL).write(to: target, options: .atomic); statusMessage = "PNG 저장 완료" }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func exportCBZ() {
        guard let book = outputBook, !isBusy, !isShowingFilePanel, results.count == pages.count, failures.isEmpty else { return }; isShowingFilePanel = true
        let panel = NSSavePanel(); panel.nameFieldStringValue = title + "_한국어.cbz"; panel.directoryURL = outputRoot
        Task {
            let response = await ComicOpenPanel.present(panel); isShowingFilePanel = false
            guard response == .OK, let target = panel.url else { return }
            beginCBZExport(book: book, target: target)
        }
    }
    private func beginCBZExport(book: TranslationBook, target: URL) {
        isBusy = true; statusMessage = "완성본을 CBZ로 묶는 중…"
        job = Task {
            defer { isBusy = false; job = nil }
            do { try await CBZExporter().export(pages: results.keys.sorted().map { book.pageURL(at: $0) }, to: target); statusMessage = "CBZ 저장 완료" }
            catch is CancellationError { statusMessage = "CBZ 저장을 중단했습니다." }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
