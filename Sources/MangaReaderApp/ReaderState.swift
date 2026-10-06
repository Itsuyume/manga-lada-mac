import AppKit
import Combine
import MangaLadaCore
import MangaLadaImport
import MangaLadaViewerUI

@MainActor
final class ReaderState: ObservableObject {
    @Published private(set) var pages: [ImagePage] = []
    @Published private(set) var index = 0
    @Published private(set) var title = ""
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var bookmarks: Set<Int> = []
    let reading = ReadingSettings(prefix: "reader")
    private let loader: ComicBookLoader
    private var bookKey = ""
    private var sourceURL: URL?
    private var loadID = UUID()
    private var isShowingFilePanel = false
    init() {
        let support = MangaLadaEdition.applicationSupport.appendingPathComponent("Archives")
        loader = ComicBookLoader(extractionRoot: support)
    }
    func chooseBook(folderOnly: Bool = false) {
        guard !isShowingFilePanel else { return }; isShowingFilePanel = true
        Task {
            defer { isShowingFilePanel = false }
            do {
                guard let input = try await ComicOpenPanel.choose(folderOnly: folderOnly) else { return }
                await open(input)
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func open(_ url: URL) async {
        await open(.file(url))
    }
    func open(_ input: ComicInput) async {
        let id = UUID(); loadID = id; isLoading = true
        do {
            let book = try await loader.load(input)
            guard loadID == id else { return }
            pages = book.pages; title = book.title; sourceURL = book.sourceURL
            bookKey = "reader." + ImageFingerprint().make(for: Data(book.sourceURL.standardizedFileURL.path.utf8))
            let saved = UserDefaults.standard.object(forKey: bookKey + ".page") as? Int
            let requested: Int
            switch input {
            case .imageInFolder: requested = book.initialIndex
            case .file(let url) where ImageFileScanner.isSupportedImage(url): requested = book.initialIndex
            default: requested = saved ?? book.initialIndex
            }
            index = min(pages.count - 1, max(0, requested))
            bookmarks = Set(UserDefaults.standard.array(forKey: bookKey + ".bookmarks") as? [Int] ?? [])
            isLoading = false
        } catch { if loadID == id { isLoading = false; errorMessage = error.localizedDescription } }
    }
    func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        self.index = index; UserDefaults.standard.set(index, forKey: bookKey + ".page")
    }
    func openInTranslator() {
        guard let sourceURL else { return }
        Task {
            do { try await CompanionApplication.translator.open(sourceURL) }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func next() { select(reading.navigation(count: pages.count).next(from: index)) }
    func previous() { select(reading.navigation(count: pages.count).previous(from: index)) }
    func toggleBookmark() {
        guard !pages.isEmpty else { return }
        if bookmarks.contains(index) { bookmarks.remove(index) } else { bookmarks.insert(index) }
        UserDefaults.standard.set(bookmarks.sorted(), forKey: bookKey + ".bookmarks")
    }
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
}
