import AppKit
import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering
import MangaLadaVision
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var pages: [ImagePage] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var renderedTranslationImage: NSImage?
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
    private let archiveExtractor: ArchiveExtractor
    private let ballonsEngine: BallonsTranslatorEngine
    private let translatedImageRenderer: TranslatedImageRenderer
    private let ocrService: VisionOCRService
    private let translator: TextTranslating
    private var renderedTranslationImageURL: URL?
    private var preferredExportDirectory: URL?

    init(
        scanner: ImageFileScanner = ImageFileScanner(),
        fingerprintMaker: ImageFingerprint = ImageFingerprint(),
        cache: TranslationCache = TranslationCache(cacheDirectory: AppPaths.cacheDirectory),
        archiveExtractor: ArchiveExtractor = ArchiveExtractor(extractionRoot: AppPaths.archiveDirectory),
        ballonsEngine: BallonsTranslatorEngine = BallonsTranslatorEngine.standard(
            applicationSupportDirectory: AppPaths.applicationSupportDirectory
        ),
        translatedImageRenderer: TranslatedImageRenderer = TranslatedImageRenderer(),
        ocrService: VisionOCRService = VisionOCRService(),
        translator: TextTranslating = GoogleWebTranslator()
    ) {
        self.scanner = scanner
        self.fingerprintMaker = fingerprintMaker
        self.cache = cache
        self.archiveExtractor = archiveExtractor
        self.ballonsEngine = ballonsEngine
        self.translatedImageRenderer = translatedImageRenderer
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

    var canExportCurrentTranslation: Bool {
        if renderedTranslationImageURL != nil {
            return true
        }

        guard let translation else {
            return false
        }
        return translation.blocks.contains { block in
            !block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func openFileFromPanel() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.openableContentTypes

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        await openURL(selectedURL)
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

    func openURL(_ url: URL) async {
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                await openFolder(url)
                return
            }

            if ImageFileScanner.isSupportedImage(url) {
                await openImage(url)
                return
            }

            if ArchiveExtractor.isSupportedArchive(url) {
                await openArchive(url)
                return
            }

            errorMessage = "지원하지 않는 파일 형식입니다: \(url.lastPathComponent)"
        } catch {
            show(error, prefix: "파일을 열지 못했습니다.")
        }
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
            preferredExportDirectory = imageURL.deletingLastPathComponent()
            try await loadCurrentPage()
        } catch {
            show(error, prefix: "이미지 폴더를 읽지 못했습니다.")
        }
    }

    func openFolder(_ folderURL: URL) async {
        do {
            let imagePages = try scanner.images(in: folderURL, recursive: false)

            guard !imagePages.isEmpty else {
                errorMessage = "폴더 안에서 지원되는 이미지 파일을 찾지 못했습니다."
                return
            }

            pages = imagePages
            currentIndex = 0
            preferredExportDirectory = folderURL
            try await loadCurrentPage()
        } catch {
            show(error, prefix: "폴더를 열지 못했습니다.")
        }
    }

    func openArchive(_ archiveURL: URL) async {
        guard ArchiveExtractor.isSupportedArchive(archiveURL) else {
            errorMessage = "지원하지 않는 압축 파일입니다: \(archiveURL.lastPathComponent)"
            return
        }

        isBusy = true
        errorMessage = nil
        statusMessage = "ZIP 압축 해제 중..."

        do {
            let extractor = archiveExtractor
            let extractedFolderURL = try await Task.detached(priority: .userInitiated) {
                try extractor.extract(archiveURL)
            }.value

            let imagePages = try scanner.images(in: extractedFolderURL, recursive: true)
            guard !imagePages.isEmpty else {
                throw AppStateError.archiveContainsNoImages(archiveURL)
            }

            pages = imagePages
            currentIndex = 0
            preferredExportDirectory = archiveURL.deletingLastPathComponent()
            try await loadCurrentPage()
            statusMessage = "\(archiveURL.lastPathComponent): \(imagePages.count)개 이미지"
        } catch {
            show(error, prefix: "압축 파일을 열지 못했습니다.")
        }

        isBusy = false
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
        await openURL(url)
    }

    func translateCurrentPage(force: Bool = false) async {
        guard let page = currentPage else {
            errorMessage = "먼저 이미지를 열어주세요."
            return
        }

        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        statusMessage = "번역 준비 중..."

        do {
            let baseFingerprint = try fingerprintMaker.make(for: page.url)
            let fingerprint = cacheFingerprint(baseFingerprint: baseFingerprint)

            if ballonsEngine.isInstalled {
                try await translateWithBallons(page: page, fingerprint: fingerprint, force: force)
                return
            }

            try await translateWithVision(page: page, fingerprint: fingerprint, force: force)
        } catch {
            show(error, prefix: "번역에 실패했습니다.")
        }
    }

    func clearCurrentCacheAndRetranslate() async {
        guard let page = currentPage else {
            return
        }

        do {
            let baseFingerprint = try fingerprintMaker.make(for: page.url)
            let fingerprint = cacheFingerprint(baseFingerprint: baseFingerprint)
            try cache.delete(fingerprint: fingerprint)
            if ballonsEngine.isInstalled {
                try ballonsEngine.clearRun(runID: fingerprint)
            }
            await translateCurrentPage(force: true)
        } catch {
            show(error, prefix: "캐시를 지우지 못했습니다.")
        }
    }

    func exportCurrentTranslatedImage() async {
        guard let page = currentPage else {
            errorMessage = "먼저 이미지를 열어주세요."
            return
        }

        guard translation != nil || renderedTranslationImageURL != nil else {
            errorMessage = "먼저 번역을 실행해주세요."
            return
        }

        guard canExportCurrentTranslation else {
            errorMessage = "저장할 번역 결과가 없습니다."
            return
        }

        guard let destinationURL = translatedImageDestinationURL(for: page.url) else {
            return
        }

        isBusy = true
        errorMessage = nil
        statusMessage = "번역본 PNG 저장 중..."

        do {
            if let renderedTranslationImageURL {
                if renderedTranslationImageURL.standardizedFileURL != destinationURL.standardizedFileURL {
                    let fileManager = FileManager.default
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        try fileManager.removeItem(at: destinationURL)
                    }
                    try fileManager.copyItem(at: renderedTranslationImageURL, to: destinationURL)
                }
                statusMessage = "번역본 저장 완료: \(destinationURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
            } else if let translation {
                let rendered = try translatedImageRenderer.writePNG(
                    sourceImageURL: page.url,
                    translation: translation,
                    destinationURL: destinationURL,
                    fontScale: overlayFontScale
                )
                statusMessage = "번역본 저장 완료: \(rendered.url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([rendered.url])
            }
        } catch {
            show(error, prefix: "번역본 저장에 실패했습니다.")
        }

        isBusy = false
    }

    private func loadCurrentPage() async throws {
        guard let page = currentPage else {
            currentImage = nil
            renderedTranslationImage = nil
            renderedTranslationImageURL = nil
            translation = nil
            statusMessage = "이미지 또는 폴더를 열어주세요."
            return
        }

        guard let image = NSImage(contentsOf: page.url) else {
            throw AppStateError.imageLoadFailed(page.url)
        }

        currentImage = image
        renderedTranslationImage = nil
        renderedTranslationImageURL = nil
        mode = .imageOnly
        statusMessage = page.url.lastPathComponent
        errorMessage = nil

        let baseFingerprint = try fingerprintMaker.make(for: page.url)
        let fingerprint = cacheFingerprint(baseFingerprint: baseFingerprint)
        translation = try cache.load(fingerprint: fingerprint)
        if translation != nil {
            statusMessage = "캐시 있음: \(page.url.lastPathComponent)"
            if ballonsEngine.isInstalled {
                let renderedURL = ballonsEngine.renderedImageURL(runID: fingerprint)
                if let renderedImage = NSImage(contentsOf: renderedURL) {
                    renderedTranslationImage = renderedImage
                    renderedTranslationImageURL = renderedURL
                    statusMessage = "고품질 캐시 있음: \(page.url.lastPathComponent)"
                }
            }
        }

        if autoTranslate {
            await translateCurrentPage(force: false)
        }
    }

    private func translateWithBallons(page: ImagePage, fingerprint: String, force: Bool) async throws {
        renderedTranslationImage = nil
        renderedTranslationImageURL = nil

        if !force, let cached = try cache.load(fingerprint: fingerprint) {
            let renderedURL = ballonsEngine.renderedImageURL(runID: fingerprint)
            if let renderedImage = NSImage(contentsOf: renderedURL) {
                translation = cached
                renderedTranslationImage = renderedImage
                renderedTranslationImageURL = renderedURL
                mode = .translated
                statusMessage = "고품질 캐시에서 번역을 불러왔습니다."
                return
            }
        }

        statusMessage = "BallonsTranslator로 텍스트 검출/OCR/번역/식자 중..."
        let engine = ballonsEngine
        let result = try await Task.detached(priority: .userInitiated) {
            try engine.translate(
                sourceImageURL: page.url,
                runID: fingerprint,
                imageFingerprint: fingerprint
            )
        }.value

        guard let renderedImage = NSImage(contentsOf: result.renderedImageURL) else {
            throw AppStateError.imageLoadFailed(result.renderedImageURL)
        }

        try cache.save(result.pageTranslation)
        translation = result.pageTranslation
        renderedTranslationImage = renderedImage
        renderedTranslationImageURL = result.renderedImageURL
        mode = .translated
        statusMessage = "고품질 번역 완료: \(result.pageTranslation.blocks.count)개 텍스트 블록"
    }

    private func translateWithVision(page: ImagePage, fingerprint: String, force: Bool) async throws {
        renderedTranslationImage = nil
        renderedTranslationImageURL = nil

        if !force, let cached = try cache.load(fingerprint: fingerprint) {
            translation = cached
            mode = .translated
            statusMessage = "내장 OCR 캐시에서 번역을 불러왔습니다."
            return
        }

        statusMessage = "내장 Vision OCR로 일본어 텍스트 인식 중..."
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
    }

    private func cacheFingerprint(baseFingerprint: String) -> String {
        let engineVersion = ballonsEngine.isInstalled ? "ballons-v1" : "vision-v2"
        return "\(baseFingerprint)-\(engineVersion)"
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

    private func translatedImageDestinationURL(for sourceURL: URL) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + "_ko.png"
        panel.directoryURL = preferredExportDirectory ?? sourceURL.deletingLastPathComponent()
        panel.title = "번역본 이미지 저장"
        panel.message = "번역 오버레이를 실제 PNG 이미지로 저장합니다."

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }
}

private enum AppStateError: LocalizedError {
    case imageLoadFailed(URL)
    case archiveContainsNoImages(URL)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let url):
            return "이미지를 불러올 수 없습니다: \(url.lastPathComponent)"
        case .archiveContainsNoImages(let url):
            return "압축 파일 안에서 지원되는 이미지 파일을 찾지 못했습니다: \(url.lastPathComponent)"
        }
    }
}

private enum AppPaths {
    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Manga Lada", isDirectory: true)
    }

    static var cacheDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("Cache", isDirectory: true)
    }

    static var archiveDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("Archives", isDirectory: true)
    }
}

private extension AppState {
    static var openableContentTypes: [UTType] {
        var types: [UTType] = [.image]
        if let zip = UTType(filenameExtension: "zip") {
            types.append(zip)
        }
        if let cbz = UTType(filenameExtension: "cbz") {
            types.append(cbz)
        }
        return types
    }
}
