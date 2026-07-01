import Foundation
import MangaLadaCore

@main
struct MangaLadaCoreChecks {
    static func main() async throws {
        try checkImageScannerKeepsOnlySupportedImagesAndSortsNaturally()
        try checkImageScannerFindsNestedImagesNaturally()
        try checkArchiveExtractorExtractsZipForRecursiveScanning()
        try checkCacheRoundTripsTranslationByFingerprint()
        try checkGoogleTranslatorParsesNestedResponseText()
        try checkGoogleTranslatorRejectsEmptyParsedText()
        try await checkPassthroughTranslatorRejectsBlankInput()
        print("MangaLadaCoreChecks passed")
    }

    private static func checkImageScannerKeepsOnlySupportedImagesAndSortsNaturally() throws {
        let root = try temporaryDirectory()
        let names = ["10.png", "2.jpg", "note.txt", ".hidden.png", "1.webp"]

        for name in names {
            FileManager.default.createFile(
                atPath: root.appendingPathComponent(name).path,
                contents: Data()
            )
        }

        let selected = root.appendingPathComponent("2.jpg")
        let pages = try ImageFileScanner().imagesInSameFolder(as: selected)
        try require(
            pages.map(\.url.lastPathComponent) == ["1.webp", "2.jpg", "10.png"],
            "Image scanner did not filter and naturally sort images."
        )
    }

    private static func checkImageScannerFindsNestedImagesNaturally() throws {
        let root = try temporaryDirectory()
        let nested = root.appendingPathComponent("chapter")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        for url in [
            nested.appendingPathComponent("10.png"),
            nested.appendingPathComponent("2.png"),
            root.appendingPathComponent("cover.jpg"),
            root.appendingPathComponent("notes.txt")
        ] {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }

        let pages = try ImageFileScanner().images(in: root, recursive: true)
        let rootPath = root.standardizedFileURL.path
        let actualPaths = pages.map { page in
            page.url.standardizedFileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
        }
        try require(
            actualPaths == ["chapter/2.png", "chapter/10.png", "cover.jpg"],
            "Recursive scanner did not naturally sort nested images: \(actualPaths)"
        )
    }

    private static func checkArchiveExtractorExtractsZipForRecursiveScanning() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("source", isDirectory: true)
        let pages = source.appendingPathComponent("pages", isDirectory: true)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)

        FileManager.default.createFile(atPath: pages.appendingPathComponent("02.png").path, contents: Data())
        FileManager.default.createFile(atPath: pages.appendingPathComponent("01.jpg").path, contents: Data())
        FileManager.default.createFile(atPath: source.appendingPathComponent("readme.txt").path, contents: Data("skip".utf8))

        let archiveURL = root.appendingPathComponent("comic.cbz")
        try makeZip(sourceFolderURL: source, archiveURL: archiveURL)

        let extractedURL = try ArchiveExtractor(
            extractionRoot: root.appendingPathComponent("archives", isDirectory: true)
        ).extract(archiveURL)
        let imagePages = try ImageFileScanner().images(in: extractedURL, recursive: true)

        try require(
            imagePages.map(\.url.lastPathComponent) == ["01.jpg", "02.png"],
            "Archive extractor did not expose images for recursive scanning."
        )
    }

    private static func checkCacheRoundTripsTranslationByFingerprint() throws {
        let cache = TranslationCache(cacheDirectory: try temporaryDirectory())
        let page = PageTranslation(
            imageURL: URL(filePath: "/tmp/page.png"),
            imageFingerprint: "abc123",
            sourceLanguage: .japanese,
            targetLanguage: .korean,
            blocks: [
                TextBlock(
                    box: TextBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                    originalText: "テスト",
                    translatedText: "테스트",
                    confidence: 0.9
                )
            ]
        )

        try cache.save(page)
        let loaded = try requireValue(
            cache.load(fingerprint: "abc123"),
            "Cache did not load the saved page."
        )
        try require(loaded.imageFingerprint == page.imageFingerprint, "Cache fingerprint mismatch.")
        try require(loaded.blocks == page.blocks, "Cache text blocks changed during round trip.")
    }

    private static func checkGoogleTranslatorParsesNestedResponseText() throws {
        let json = #"[[["안녕","こんにちは",null,null,1]],null,"ja"]"#
        let translated = try GoogleWebTranslator.parseTranslationResponse(Data(json.utf8))
        try require(translated == "안녕", "Google response parser returned wrong text.")
    }

    private static func checkGoogleTranslatorRejectsEmptyParsedText() throws {
        let json = #"[[["","",null,null,1]],null,"ja"]"#
        do {
            _ = try GoogleWebTranslator.parseTranslationResponse(Data(json.utf8))
            throw CheckError.failed("Google response parser accepted empty translated text.")
        } catch TranslationError.missingTranslatedText {
            return
        }
    }

    private static func checkPassthroughTranslatorRejectsBlankInput() async throws {
        let translator = PassthroughTranslator()
        do {
            _ = try await translator.translate("   ", source: .japanese, target: .korean)
            throw CheckError.failed("Passthrough translator accepted blank input.")
        } catch TranslationError.emptyText {
            return
        }
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaLadaChecks")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeZip(sourceFolderURL: URL, archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qry", archiveURL.path, "."]
        process.currentDirectoryURL = sourceFolderURL

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CheckError.failed("Failed to create test zip: \(message)")
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw CheckError.failed(message)
        }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw CheckError.failed(message)
        }
        return value
    }
}

private enum CheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
