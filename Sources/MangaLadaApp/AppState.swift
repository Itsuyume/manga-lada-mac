import AppKit
import Foundation
import MangaLadaCore
import MangaLadaVision

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var pages: [ImagePage] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var translation: PageTranslation?
    @Published private(set) var isBusy = false
    @Published private(set) var statusMessage = "이미지 또는 폴더를 열어주세요."
    @Published var errorMessage: String?
    @Published var mode: AppMode = .imageOnly
    @Published var sourceLanguage: LanguageCode = .japanese
    @Published var targetLanguage: LanguageCode = .korean
    @Published var overlayFontScale: Double = 1.0
    @Published var autoTranslate = false

    private let scanner: ImageFileScanner
    private let fingerprintMaker: ImageFingerprint
    private let cache: TranslationCache
    private let ocrService: VisionOCRService
    private let translator: TextTranslating

    init(
        scanner: ImageFileScanner = ImageFileScanner(),
        fingerprintMaker: ImageFingerprint = ImageFingerprint(),
        cache: TranslationCache = TranslationCache(cacheDirectory: AppPaths.cacheDirectory),
        ocrService: VisionOCRService = VisionOCRService(),
        translator: TextTranslating = GoogleWebTranslator()
    ) {
        self.scanner = scanner
        self.fingerprintMaker = fingerprintMaker
        self.cache = cache
        self.ocrService = ocrService
        self.translator = translator
    }

    var currentPage: ImagePage? {
        guard pages.indices.contains(currentIndex) else {
            return nil
        }
        return pages[currentIndex]
    }

    var pageLabel: String {
        guard !pages.isEmpty else {
            return "0 / 0"
        }
        return "\(currentIndex + 1) / \(pages.count)"
    }

    func openImageFromPanel() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        await openImage(selectedURL)
    }

    func openFolderFromPanel() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        await openFolder(folderURL)
    }

    func openImage(_ imageURL: URL) async {
        guard ImageFileScanner.isSupportedImage(imageURL) else {
            errorMessage = "지원하지 않는 이미지 형식입니다: \(imageURL.lastPathComponent)"
            return
        }

        do {
            let folderPages = try scanner.imagesInSameFolder(as: imageURL)
            pages = folderPages.isEmpty ? [ImagePage(url: imageURL)] : folderPages
            currentIndex = pages.firstIndex { $0.url == imageURL } ?? 0
            try await loadCurrentPage()
        } catch {
            show(error, prefix: "이미지 폴더를 읽지 못했습니다.")
        }
    }

    func openFolder(_ folderURL: URL) async {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            let imagePages = contents
                .filter(ImageFileScanner.isSupportedImage)
                .sorted { lhs, rhs in
                    lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
                }
                .map(ImagePage.init(url:))

            guard !imagePages.isEmpty else {
                errorMessage = "폴더 안에서 지원되는 이미지 파일을 찾지 못했습니다."
                return
            }

            pages = imagePages
            currentIndex = 0
            try await loadCurrentPage()
        } catch {
            show(error, prefix: "폴더를 열지 못했습니다.")
        }
    }

    func goToPreviousPage() {
        guard currentIndex > 0 else {
            return
        }
        currentIndex -= 1
        Task {
            do {
                try await loadCurrentPage()
            } catch {
                show(error, prefix: "이전 페이지를 열지 못했습니다.")
            }
        }
    }

    func goToNextPage() {
        guard currentIndex + 1 < pages.count else {
            return
        }
        currentIndex += 1
        Task {
            do {
                try await loadCurrentPage()
            } catch {
                show(error, prefix: "다음 페이지를 열지 못했습니다.")
            }
        }
    }

    func openDroppedURL(_ url: URL) async {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                await openFolder(url)
                return
            }

            await openImage(url)
        } catch {
            show(error, prefix: "드롭한 파일을 열지 못했습니다.")
        }
    }

    func translateCurrentPage(force: Bool = false) async {
        guard let page = currentPage else {
            errorMessage = "먼저 이미지를 열어주세요."
            return
        }

        isBusy = true
        errorMessage = nil
        statusMessage = "OCR 준비 중..."

        do {
            let fingerprint = try fingerprintMaker.make(for: page.url)
            if !force, let cached = try cache.load(fingerprint: fingerprint) {
                translation = cached
                mode = .translated
                statusMessage = "캐시에서 번역을 불러왔습니다."
                isBusy = false
                return
            }

            statusMessage = "일본어 텍스트 인식 중..."
            let blocks = try await ocrService.recognizeText(in: page.url)
            guard !blocks.isEmpty else {
                translation = PageTranslation(
                    imageURL: page.url,
                    imageFingerprint: fingerprint,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    blocks: []
                )
                mode = .translated
                statusMessage = "인식된 텍스트가 없습니다."
                isBusy = false
                return
            }

            statusMessage = "한국어 번역 중..."
            let translatedBlocks = try await translate(blocks)
            let pageTranslation = PageTranslation(
                imageURL: page.url,
                imageFingerprint: fingerprint,
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                blocks: translatedBlocks
            )
            try cache.save(pageTranslation)
            translation = pageTranslation
            mode = .translated
            statusMessage = "번역 완료: \(translatedBlocks.count)개 텍스트 블록"
        } catch {
            show(error, prefix: "번역에 실패했습니다.")
        }

        isBusy = false
    }

    func clearCurrentCacheAndRetranslate() async {
        guard let page = currentPage else {
            return
        }

        do {
            let fingerprint = try fingerprintMaker.make(for: page.url)
            try cache.delete(fingerprint: fingerprint)
            await translateCurrentPage(force: true)
        } catch {
            show(error, prefix: "캐시를 지우지 못했습니다.")
        }
    }

    private func loadCurrentPage() async throws {
        guard let page = currentPage else {
            currentImage = nil
            translation = nil
            statusMessage = "이미지 또는 폴더를 열어주세요."
            return
        }

        guard let image = NSImage(contentsOf: page.url) else {
            throw AppStateError.imageLoadFailed(page.url)
        }

        currentImage = image
        mode = .imageOnly
        statusMessage = page.url.lastPathComponent
        errorMessage = nil

        let fingerprint = try fingerprintMaker.make(for: page.url)
        translation = try cache.load(fingerprint: fingerprint)
        if translation != nil {
            statusMessage = "캐시 있음: \(page.url.lastPathComponent)"
        }

        if autoTranslate {
            await translateCurrentPage(force: false)
        }
    }

    private func translate(_ blocks: [TextBlock]) async throws -> [TextBlock] {
        var translatedBlocks: [TextBlock] = []
        translatedBlocks.reserveCapacity(blocks.count)

        for (index, block) in blocks.enumerated() {
            statusMessage = "한국어 번역 중... \(index + 1) / \(blocks.count)"
            let translatedText = try await translator.translate(
                block.originalText,
                source: sourceLanguage,
                target: targetLanguage
            )
            var translatedBlock = block
            translatedBlock.translatedText = translatedText
            translatedBlocks.append(translatedBlock)
        }

        return translatedBlocks
    }

    private func show(_ error: Error, prefix: String) {
        errorMessage = "\(prefix) \(error.localizedDescription)"
        statusMessage = prefix
        isBusy = false
    }
}

private enum AppStateError: LocalizedError {
    case imageLoadFailed(URL)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let url):
            return "이미지를 불러올 수 없습니다: \(url.lastPathComponent)"
        }
    }
}

private enum AppPaths {
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Manga Lada", isDirectory: true)
            .appendingPathComponent("Cache", isDirectory: true)
    }
}
