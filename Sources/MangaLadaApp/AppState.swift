import AppKit
import Combine
import MangaLadaCore
import MangaLadaImport
import MangaLadaRendering
import MangaLadaViewerUI
import MangaLadaWorkflow

@MainActor
final class AppState: ObservableObject {
    @Published var pages: [ImagePage] = []
    @Published var currentIndex = 0
    @Published var title = ""
    @Published var statusMessage = "일본어 만화 파일 또는 폴더를 열어주세요."
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var isLoading = false
    @Published var showSettings = false
    @Published var showInspector = true
    @Published var mode: AppMode = .translated
    @Published var results: [Int: ProcessedMangaPage] = [:]
    @Published var reviewDrafts: [Int: PageTranslation] = [:]
    @Published var reviewErrors: [Int: String] = [:]
    @Published var failures: [Int: String] = [:]
    @Published var processingIndex: Int?
    @Published var imageRevision = 0
    @Published var configuration = LocalTranslatorConfiguration()
    @Published var typography = MangaTypography()
    @Published var effectStyles: [SoundEffectStyle] = []
    @Published var isSelectingRegion = false
    @Published var selectedRegion: TextBox?
    @Published var selectedBlockID: UUID?
    @Published var blockFocusRevision = 0
    @Published var selectedRegionKind: MangaTextKind = .dialogue
    @Published var outputRoot: URL?
    @Published var outputBook: TranslationBook?
    @Published var autoTranslate: Bool { didSet { UserDefaults.standard.set(autoTranslate, forKey: "translator.auto") } }
    let reading = ReadingSettings(prefix: "translator")
    let loader = ComicBookLoader(extractionRoot: AppPaths.archives)
    let processor = MangaPageProcessor(applicationSupportDirectory: AppPaths.support)
    let bookStore = TranslationBookStore()
    let settingsStore = TranslatorSettingsStore()
    let runtime = LocalModelRuntime()
    let reviewStore = TranslationReviewStore(directory: AppPaths.support.appendingPathComponent("ReviewDrafts"))
    var sourceURL: URL?
    var sessionID = UUID()
    var job: Task<Void, Never>?
    var isShowingFilePanel = false
    init() {
        autoTranslate = UserDefaults.standard.object(forKey: "translator.auto") as? Bool ?? true
        if let path = UserDefaults.standard.string(forKey: "translator.outputRoot") { outputRoot = URL(fileURLWithPath: path) }
        do {
            try SoundEffectFonts.registerBundledFonts()
            effectStyles = try SoundEffectLibrary.standard().styles
            (configuration, typography) = try settingsStore.load()
        }
        catch { errorMessage = error.localizedDescription; statusMessage = "설정을 읽지 못했습니다. 설정을 확인해주세요." }
    }
    var currentResult: ProcessedMangaPage? { results[currentIndex] }
    var displayPages: [URL] { pages.enumerated().map { index, page in !isSelectingRegion && mode == .translated ? results[index]?.renderedImageURL ?? page.url : page.url } }
    var completed: Set<Int> { Set(results.keys) }
    var progress: Double { pages.isEmpty ? 0 : Double(results.count + failures.count) / Double(pages.count) }
    func select(_ index: Int) {
        guard pages.indices.contains(index), index != currentIndex else { return }
        currentIndex = index; selectedRegion = nil; selectedBlockID = nil
    }
    func next() { select(reading.navigation(count: pages.count).next(from: currentIndex)) }
    func previous() { select(reading.navigation(count: pages.count).previous(from: currentIndex)) }
    func stop() { job?.cancel(); statusMessage = "현재 작업을 중단하는 중…" }
    func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123: reading.direction == .rightToLeft ? next() : previous()
        case 124: reading.direction == .rightToLeft ? previous() : next()
        case 49, 121: next()
        case 116: previous()
        case 115: select(0)
        case 119: select(pages.count - 1)
        default: return false
        }
        return true
    }
    @discardableResult
    func saveSettings(configuration: LocalTranslatorConfiguration, typography: MangaTypography, renderCompleted: Bool = true) -> Bool {
        guard !isBusy else { return false }
        guard self.configuration == configuration || requireAppliedReviews() else { return false }
        do {
            try settingsStore.save(configuration: configuration, typography: typography)
            let translatorChanged = self.configuration != configuration
            self.configuration = configuration; self.typography = typography; showSettings = false
            if translatorChanged {
                results = [:]; reviewDrafts = [:]; reviewErrors = [:]; failures = [:]; imageRevision += 1
                statusMessage = "번역 방식이 바뀌었습니다. 전체 번역 시작을 눌러 새 설정으로 번역해주세요."
            } else if renderCompleted { rerenderCompletedPages() }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func prepareLocalModel() {
        guard !isBusy else { return }; isBusy = true; statusMessage = "\(configuration.ollama.model) · 로컬 모델을 준비하는 중…"
        job = Task {
            var ready = false
            defer { isBusy = false; job = nil; if ready { rerenderCompletedPages() } }
            do { try await runtime.prepare(model: configuration.ollama.model); statusMessage = "로컬 모델 준비 완료 · 인터넷 없이 번역할 수 있습니다."; ready = true }
            catch is CancellationError { statusMessage = "모델 준비를 중단했습니다." }
            catch { statusMessage = "모델 준비 실패"; errorMessage = error.localizedDescription }
        }
    }
    private func rerenderCompletedPages() {
        guard !results.isEmpty, !isBusy else { return }
        isBusy = true
        job = Task {
            defer { isBusy = false; job = nil; processingIndex = nil }
            do {
                for index in results.keys.sorted() {
                    try Task.checkCancellation()
                    guard let result = results[index] else { continue }
                    processingIndex = index; statusMessage = "\(index + 1)페이지 · 새 글꼴로 저장 중"
                    recordResult(try processor.applyEdits(to: result, translation: result.translation, typography: typography), at: index)
                    imageRevision += 1; await Task.yield()
                }
                statusMessage = "완성한 페이지 전체에 글꼴 설정을 적용했습니다."
            } catch is CancellationError { statusMessage = "글꼴 적용을 중단했습니다." }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
