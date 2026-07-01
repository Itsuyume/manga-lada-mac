import Foundation
import MangaLadaCore

@main
struct MangaLadaCoreChecks {
    static func main() async throws {
        try checkImageScannerKeepsOnlySupportedImagesAndSortsNaturally()
        try checkImageScannerFindsNestedImagesNaturally()
        try checkArchiveExtractorExtractsZipForRecursiveScanning()
        try checkCacheRoundTripsTranslationByFingerprint()
        try checkLocalTranslatorConfigurationLoadsFileAndEnvironmentOverrides()
        try checkOllamaTranslatorResponseParser()
        try await checkOllamaTranslatorSendsLocalChatRequest()
        try await checkTranslationPipelineTranslatesAndRefinesBlocks()
        try await checkTranslationPipelineRunsNonBatchRequestsConcurrently()
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

    private static func checkLocalTranslatorConfigurationLoadsFileAndEnvironmentOverrides() throws {
        let root = try temporaryDirectory()
        let configURL = root.appendingPathComponent("translator.local.json")
        let json = """
        {
          "maxConcurrentRequests": 3,
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
                "MANGA_LADA_MAX_CONCURRENT_TRANSLATIONS": "6",
                "MANGA_LADA_OLLAMA_MODEL": "env-ollama"
            ]
        )

        try require(configuration.maxConcurrentRequests == 6, "Environment did not override concurrency.")
        try require(configuration.ollama.model == "env-ollama", "Environment did not override Ollama model.")
        try require(configuration.ollama.endpoint.absoluteString == "http://127.0.0.1:11434", "Ollama endpoint was not loaded.")
        try require(configuration.cacheKey == "ollama-env-ollama", "Ollama cache key did not include model.")
    }

    private static func checkOllamaTranslatorResponseParser() throws {
        let ollamaJSON = #"{"message":{"role":"assistant","content":"```ko\n좋습니다\n```"}}"#
        let ollama = try OllamaTranslator.parseTranslationResponse(Data(ollamaJSON.utf8))
        try require(ollama == "좋습니다", "Ollama response parser returned wrong text.")

        let labeledOllamaJSON = #"{"message":{"role":"assistant","content":"単純文本 翻译：안녕하세요"}}"#
        let labeledOllama = try OllamaTranslator.parseTranslationResponse(Data(labeledOllamaJSON.utf8))
        try require(labeledOllama == "안녕하세요", "Ollama parser did not remove translation labels.")

        let mixedScriptOllamaJSON = #"{"message":{"role":"assistant","content":"천왕사-san自身的話이라니"}}"#
        let mixedScriptOllama = try OllamaTranslator.parseTranslationResponse(Data(mixedScriptOllamaJSON.utf8))
        try require(mixedScriptOllama == "천왕사 이라니", "Ollama parser did not remove source-script residue.")
    }

    private static func checkOllamaTranslatorSendsLocalChatRequest() async throws {
        let session = mockSession { request in
            try require(request.url?.path == "/api/chat", "Ollama endpoint was not normalized to /api/chat.")
            try require(request.value(forHTTPHeaderField: "Authorization") == nil, "Ollama request should not send bearer auth.")
            let body = try jsonObject(from: request) as? [String: Any]
            try require(body?["model"] as? String == "gemma3:4b", "Ollama model mismatch.")
            try require(body?["stream"] as? Bool == false, "Ollama request must disable streaming.")
            let messages = body?["messages"] as? [[String: String]]
            try require(messages?.last?["content"] == "こんにちは", "Ollama user message mismatch.")

            return okJSON(#"{"message":{"role":"assistant","content":"안녕하세요"}}"#, for: request)
        }

        let translator = OllamaTranslator(
            endpoint: URL(string: "http://mock.test")!,
            model: "gemma3:4b",
            session: session
        )
        let translated = try await translator.translate("こんにちは", source: .japanese, target: .korean)
        try require(translated == "안녕하세요", "Ollama translation returned wrong text.")
    }

    private static func checkTranslationPipelineTranslatesAndRefinesBlocks() async throws {
        let recorder = TextCallRecorder()
        let translator = FixedSpyTranslator(
            recorder: recorder,
            translatedTexts: ["텐 노지\n씨의 만화", "자종"]
        )
        let configuration = LocalTranslatorConfiguration(maxConcurrentRequests: 1)
        let blocks = [
            TextBlock(
                box: TextBox(x: 0, y: 0, width: 0.1, height: 0.1),
                originalText: "天王寺さんのまんこっと"
            ),
            TextBlock(
                box: TextBox(x: 0, y: 0.2, width: 0.1, height: 0.1),
                originalText: "子種"
            )
        ]
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean)
        let translated = try await pipeline.translate(
            blocks,
            configuration: configuration,
            translator: translator
        )

        try require(translated.map(\.translatedText) == ["텐노지\n씨의 보지", "정액"], "Pipeline did not refine translated blocks.")
        try require(await recorder.texts == ["天王寺さんのまんこっと", "子種"], "Pipeline did not preserve source block order.")
    }

    private static func checkTranslationPipelineRunsNonBatchRequestsConcurrently() async throws {
        let recorder = ParallelCallRecorder()
        let translator = SlowSpyTranslator(recorder: recorder)
        let configuration = LocalTranslatorConfiguration(maxConcurrentRequests: 2)
        let blocks = [
            TextBlock(box: TextBox(x: 0, y: 0, width: 0.1, height: 0.1), originalText: "一"),
            TextBlock(box: TextBox(x: 0, y: 0.2, width: 0.1, height: 0.1), originalText: "二"),
            TextBlock(box: TextBox(x: 0, y: 0.4, width: 0.1, height: 0.1), originalText: "三")
        ]
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean)
        let translated = try await pipeline.translate(
            blocks,
            configuration: configuration,
            translator: translator
        )

        try require(translated.map(\.translatedText) == ["번역: 一", "번역: 二", "번역: 三"], "Concurrent pipeline did not preserve result order.")
        try require(await recorder.maxActive == 2, "Concurrent pipeline did not honor maxConcurrentRequests.")
        try require(await recorder.startedTexts == ["一", "二", "三"], "Concurrent pipeline did not submit all source blocks.")
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

    private static func mockSession(
        handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> URLSession {
        MockURLProtocol.requestCount = 0
        MockURLProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func okJSON(_ json: String, for request: URLRequest) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }

    private static func jsonObject(from request: URLRequest) throws -> Any {
        guard let data = bodyData(from: request) else {
            throw CheckError.failed("Request has no JSON body.")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
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

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requestCount += 1
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: CheckError.failed("Mock URL handler missing."))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor TextCallRecorder {
    private var nextIndex = 0
    private(set) var texts: [String] = []

    func record(_ text: String) -> Int {
        let index = nextIndex
        nextIndex += 1
        texts.append(text)
        return index
    }
}

private struct FixedSpyTranslator: TextTranslating {
    let recorder: TextCallRecorder
    let translatedTexts: [String]

    func translate(_ text: String, source: LanguageCode, target: LanguageCode) async throws -> String {
        let index = await recorder.record(text)
        return translatedTexts[index]
    }
}

private actor ParallelCallRecorder {
    private(set) var active = 0
    private(set) var maxActive = 0
    private(set) var startedTexts: [String] = []

    func start(_ text: String) {
        active += 1
        maxActive = max(maxActive, active)
        startedTexts.append(text)
    }

    func finish() {
        active -= 1
    }
}

private struct SlowSpyTranslator: TextTranslating {
    let recorder: ParallelCallRecorder

    func translate(_ text: String, source: LanguageCode, target: LanguageCode) async throws -> String {
        await recorder.start(text)
        try await Task.sleep(nanoseconds: 50_000_000)
        await recorder.finish()
        return "번역: \(text)"
    }
}
