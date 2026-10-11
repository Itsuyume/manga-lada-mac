import AppKit
import MangaLadaImport
import MangaLadaViewerUI
import UniformTypeIdentifiers

extension AppState {
    /// Every page has a saved translation, no page failed or waits for review.
    var isBookComplete: Bool {
        !pages.isEmpty && failures.isEmpty && pendingPages.isEmpty && pages.indices.allSatisfy { results[$0] != nil }
    }
    var canExportBook: Bool { isBookComplete && !isBusy && !isLoading }

    /// Saves the whole finished book through the Finder save panel. A one-page book is saved as a
    /// PNG file; a multi-page book becomes a new folder that mirrors the source folder layout.
    func exportBook() {
        guard !isBusy, !isLoading, !isShowingFilePanel, !pages.isEmpty else { return }
        guard canExportBook else {
            statusMessage = "모든 페이지의 번역을 끝내야 전체 저장할 수 있습니다. 실패·검수 필요 페이지를 먼저 확인해주세요."
            return
        }
        guard requireAppliedReviews() else { return }
        let rendered = pages.indices.compactMap { results[$0]?.renderedImageURL }
        guard rendered.count == pages.count else { return }
        let single = pages.count == 1
        let panel = NSSavePanel()
        panel.canCreateDirectories = true; panel.directoryURL = outputRoot
        panel.title = "번역 완성본 전체 저장"; panel.prompt = "전체 저장"
        if single {
            panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = exportName(single: true) + ".png"
            panel.message = "번역한 페이지를 PNG 파일로 저장합니다."
        } else {
            panel.nameFieldStringValue = exportName(single: false)
            panel.message = "이 이름으로 새 폴더를 만들고 원본과 같은 폴더 구성·파일 이름으로 \(pages.count)쪽을 PNG로 저장합니다."
        }
        isShowingFilePanel = true
        let sources = pages.map(\.url), id = sessionID
        Task {
            let response = await ComicOpenPanel.present(panel); isShowingFilePanel = false
            guard response == .OK, let target = panel.url, sessionID == id else { return }
            beginBookExport(rendered: rendered, sources: sources, target: target, single: single)
        }
    }

    private func beginBookExport(rendered: [URL], sources: [URL], target: URL, single: Bool) {
        guard !isBusy else { return }
        isBusy = true; statusMessage = "전체 \(rendered.count)쪽을 저장하는 중…"
        let id = sessionID
        job = Task {
            defer { if sessionID == id { isBusy = false; job = nil } }
            do {
                if single {
                    try Data(contentsOf: rendered[0]).write(to: target, options: .atomic)
                } else {
                    let layout = try TranslatedBookExporter.layout(rendered: rendered, sources: sources)
                    try await TranslatedBookExporter().export(layout, to: target)
                }
                guard sessionID == id else { return }
                statusMessage = "전체 저장 완료 · \(target.lastPathComponent) (\(rendered.count)쪽)"
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch is CancellationError {
                if sessionID == id { statusMessage = "전체 저장을 중단했습니다. 기존 파일은 바뀌지 않았습니다." }
            } catch {
                if sessionID == id { statusMessage = "전체 저장 실패"; errorMessage = error.localizedDescription }
            }
        }
    }

    /// The book title (or a single page's own name) with path separators removed.
    private func exportName(single: Bool) -> String {
        let stem = pages.first?.url.deletingPathExtension().lastPathComponent ?? ""
        let generated = stem.isEmpty || stem.allSatisfy(\.isNumber) || UUID(uuidString: stem) != nil
        let base = single && !generated ? stem : title
        let safe = base.components(separatedBy: CharacterSet(charactersIn: "/:\n\r")).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces).prefix(100)
        return (safe.isEmpty ? "만화" : String(safe)) + "_한국어"
    }
}
