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
        try checkLocalTranslatorConfigurationLoadsFileAndEnvironmentOverrides()
        try checkAPITranslatorResponseParsers()
        try checkKoreanTranslationRefinerFixesKnownMistranslations()
        try checkKoreanTranslationRefinerLeavesUnrelatedTextAlone()
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

    private static func checkLocalTranslatorConfigurationLoadsFileAndEnvironmentOverrides() throws {
        let root = try temporaryDirectory()
        let configURL = root.appendingPathComponent("translator.local.json")
        let json = """
        {
          "provider": "deepl",
          "maxConcurrentRequests": 3,
          "deepl": {
            "apiKey": "file-deepl-key",
            "endpoint": "https://api-free.deepl.com/v2/translate",
            "context": "manga dialogue"
          },
          "papago": {
            "clientId": "file-client-id",
            "clientSecret": "file-client-credential"
          },
          "llm": {
            "endpoint": "https://example.test/v1",
            "model": "file-model"
          },
          "ollama": {
            "endpoint": "http://127.0.0.1:11434",
            "model": "file-ollama"
          }
        }
        """
        try json.write(to: configURL, atomically: true, encoding: .utf8)

        let configuration = try LocalTranslatorConfiguration.load(
            configURL: configURL,
            environment: [
                "MANGA_LADA_TRANSLATOR": "papago",
                "MANGA_LADA_MAX_CONCURRENT_TRANSLATIONS": "6",
                "MANGA_LADA_DEEPL_API_KEY": "env-deepl-key",
                "MANGA_LADA_LLM_MODEL": "env-model"
            ]
        )

        try require(configuration.defaultProvider == .papago, "Environment did not override provider.")
        try require(configuration.maxConcurrentRequests == 6, "Environment did not override concurrency.")
        try require(configuration.deepl.apiKey == "env-deepl-key", "Environment did not override DeepL key.")
        try require(configuration.deepl.context == "manga dialogue", "DeepL context was not loaded from file.")
        try require(configuration.papago.clientID == "file-client-id", "Papago client ID was not loaded.")
        try require(configuration.llm.model == "env-model", "Environment did not override LLM model.")
        try require(configuration.cacheKey(for: .llm) == "llm-env-model", "LLM cache key did not include model.")
    }

    private static func checkAPITranslatorResponseParsers() throws {
        let deeplJSON = #"{"translations":[{"text":"안녕"},{"text":"세계"}]}"#
        let deepl = try DeepLTranslator.parseTranslationResponse(Data(deeplJSON.utf8))
        try require(deepl == ["안녕", "세계"], "DeepL response parser returned wrong texts.")

        let papagoJSON = #"{"message":{"result":{"translatedText":"안녕하세요"}}}"#
        let papago = try PapagoTranslator.parseTranslationResponse(Data(papagoJSON.utf8))
        try require(papago == "안녕하세요", "Papago response parser returned wrong text.")

        let chatJSON = #"{"choices":[{"message":{"role":"assistant","content":"\"좋아요\""}}]}"#
        let chat = try OpenAICompatibleTranslator.parseTranslationResponse(Data(chatJSON.utf8))
        try require(chat == "좋아요", "OpenAI-compatible response parser returned wrong text.")

        let ollamaJSON = #"{"message":{"role":"assistant","content":"```ko\n좋습니다\n```"}}"#
        let ollama = try OllamaTranslator.parseTranslationResponse(Data(ollamaJSON.utf8))
        try require(ollama == "좋습니다", "Ollama response parser returned wrong text.")
    }

    private static func checkKoreanTranslationRefinerFixesKnownMistranslations() throws {
        let refiner = KoreanTranslationRefiner()

        let explicitTerm = refiner.refine(
            originalText: "天王寺さんのまんこっと",
            translatedText: "텐 노지\n씨의 만화"
        )
        try require(explicitTerm == "텐노지\n씨의 보지", "Refiner did not fix the known explicit-term mistranslation.")

        let seedTerm = refiner.refine(
            originalText: "子種を注がれる",
            translatedText: "자종을 부어 넣는다"
        )
        try require(seedTerm == "정액을 부어 넣는다", "Refiner did not fix 子種 mistranslation.")

        let honorificTerm = refiner.refine(
            originalText: "殿方の劣情",
            translatedText: "전방의 열정"
        )
        try require(honorificTerm == "남성분의 욕정", "Refiner did not fix source-aware adult context terms.")

        let seedAction = refiner.refine(
            originalText: "子種をこすりつけてきますのよ",
            translatedText: "자종을\n문지릅니다."
        )
        try require(seedAction == "정액을 문질러 묻힙니다.", "Refiner did not fix line-broken seed action text.")
    }

    private static func checkKoreanTranslationRefinerLeavesUnrelatedTextAlone() throws {
        let refiner = KoreanTranslationRefiner()
        let unrelated = refiner.refine(
            originalText: "漫画を読みます",
            translatedText: "만화를 읽습니다"
        )
        try require(unrelated == "만화를 읽습니다", "Refiner changed unrelated manga text.")
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
