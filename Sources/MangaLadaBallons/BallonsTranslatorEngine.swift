import Foundation
import CoreGraphics
import ImageIO
import MangaLadaCore

public struct BallonsTranslationResult: Sendable {
    public let pageTranslation: PageTranslation
    public let renderedImageURL: URL
    public let inpaintedImageURL: URL
    public let sourceTextURL: URL?
    public let translationTextURL: URL?
}

public enum BallonsTranslatorEngineError: LocalizedError, Equatable {
    case engineNotInstalled
    case sourceImageConversionFailed(String)
    case processFailed(Int32, String)
    case projectFileMissing(URL)
    case resultImageMissing(URL)
    case inpaintedImageMissing(URL)
    case invalidImageSize(URL)
    case noTextBlocks

    public var errorDescription: String? {
        switch self {
        case .engineNotInstalled:
            return "BallonsTranslator 엔진이 설치되어 있지 않습니다. scripts/setup_ballons_engine.sh를 먼저 실행해주세요."
        case .sourceImageConversionFailed(let detail):
            return "Ballons 입력 PNG를 만들지 못했습니다. \(detail)"
        case .processFailed(let code, let log):
            return "BallonsTranslator 실행 실패(code \(code)). \(log)"
        case .projectFileMissing(let url):
            return "Ballons 결과 JSON을 찾지 못했습니다: \(url.path)"
        case .resultImageMissing(let url):
            return "Ballons 결과 PNG를 찾지 못했습니다: \(url.path)"
        case .inpaintedImageMissing(let url):
            return "Ballons 원문 제거 PNG를 찾지 못했습니다: \(url.path)"
        case .invalidImageSize(let url):
            return "이미지 크기를 읽지 못했습니다: \(url.lastPathComponent)"
        case .noTextBlocks:
            return "BallonsTranslator가 텍스트 블록을 찾지 못했습니다."
        }
    }
}

public struct BallonsTranslatorEngine: Sendable {
    public let pythonURL: URL
    public let sourceRootURL: URL
    public let runsDirectoryURL: URL

    public init(pythonURL: URL, sourceRootURL: URL, runsDirectoryURL: URL) {
        self.pythonURL = pythonURL
        self.sourceRootURL = sourceRootURL
        self.runsDirectoryURL = runsDirectoryURL
    }

    public static func standard(applicationSupportDirectory: URL) -> BallonsTranslatorEngine {
        BallonsTranslatorEngine(
            pythonURL: applicationSupportDirectory
                .appendingPathComponent("ballons-engine", isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("python"),
            sourceRootURL: applicationSupportDirectory
                .appendingPathComponent("BallonsTranslator-dev", isDirectory: true),
            runsDirectoryURL: applicationSupportDirectory
                .appendingPathComponent("BallonsRuns", isDirectory: true)
        )
    }

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: pythonURL.path)
            && FileManager.default.fileExists(
                atPath: sourceRootURL.appendingPathComponent("ballontranslator", isDirectory: true).path
            )
    }

    public func renderedImageURL(runID: String) -> URL {
        runDirectoryURL(runID: runID)
            .appendingPathComponent("result", isDirectory: true)
            .appendingPathComponent(Self.inputImageName)
    }

    public func inpaintedImageURL(runID: String) -> URL {
        runDirectoryURL(runID: runID)
            .appendingPathComponent("inpainted", isDirectory: true)
            .appendingPathComponent(Self.inputImageName)
    }

    public func mangaLadaRenderedImageURL(runID: String) -> URL {
        runDirectoryURL(runID: runID).appendingPathComponent("manga-lada-rendered.png")
    }

    public func clearRun(runID: String) throws {
        let runDirectory = runDirectoryURL(runID: runID)
        guard FileManager.default.fileExists(atPath: runDirectory.path) else {
            return
        }
        try FileManager.default.removeItem(at: runDirectory)
    }

    public func translate(
        sourceImageURL: URL,
        runID: String,
        imageFingerprint: String,
        enableTranslation: Bool = true
    ) throws -> BallonsTranslationResult {
        guard isInstalled else {
            throw BallonsTranslatorEngineError.engineNotInstalled
        }

        let runDirectory = runDirectoryURL(runID: runID)
        try resetRunDirectory(runDirectory)

        let inputURL = runDirectory.appendingPathComponent(Self.inputImageName)
        try convertToPNG(sourceImageURL: sourceImageURL, destinationURL: inputURL)

        let configURL = runDirectory.appendingPathComponent("manga-lada-ballons-config.json")
        try Self.configJSON(enableTranslation: enableTranslation).write(to: configURL, atomically: true, encoding: .utf8)

        try runBallons(runDirectory: runDirectory, configURL: configURL)

        let resultURL = renderedImageURL(runID: runID)
        guard FileManager.default.fileExists(atPath: resultURL.path) else {
            throw BallonsTranslatorEngineError.resultImageMissing(resultURL)
        }
        let inpaintedURL = inpaintedImageURL(runID: runID)
        guard FileManager.default.fileExists(atPath: inpaintedURL.path) else {
            throw BallonsTranslatorEngineError.inpaintedImageMissing(inpaintedURL)
        }

        let projectURL = runDirectory.appendingPathComponent("imgtrans_\(runDirectory.lastPathComponent).json")
        guard FileManager.default.fileExists(atPath: projectURL.path) else {
            throw BallonsTranslatorEngineError.projectFileMissing(projectURL)
        }

        let pageTranslation = try parseTranslation(
            projectURL: projectURL,
            sourceImageURL: sourceImageURL,
            imageFingerprint: imageFingerprint,
            imageSize: imageSize(for: inputURL)
        )

        return BallonsTranslationResult(
            pageTranslation: pageTranslation,
            renderedImageURL: resultURL,
            inpaintedImageURL: inpaintedURL,
            sourceTextURL: optionalFile(in: runDirectory, suffix: "_source.txt"),
            translationTextURL: optionalFile(in: runDirectory, suffix: "_translation.txt")
        )
    }

    private func runDirectoryURL(runID: String) -> URL {
        runsDirectoryURL.appendingPathComponent(runID, isDirectory: true)
    }

    private func resetRunDirectory(_ runDirectory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: runDirectory.path) {
            try fileManager.removeItem(at: runDirectory)
        }
        try fileManager.createDirectory(at: runDirectory, withIntermediateDirectories: true)
    }

    private func convertToPNG(sourceImageURL: URL, destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-s", "format", "png", sourceImageURL.path, "--out", destinationURL.path]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "sips failed"
            throw BallonsTranslatorEngineError.sourceImageConversionFailed(message)
        }
    }

    private func runBallons(runDirectory: URL, configURL: URL) throws {
        let logURL = runDirectory.appendingPathComponent("ballons.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        defer {
            try? logHandle.close()
        }

        let inputPipe = Pipe()
        let process = Process()
        process.executableURL = pythonURL
        process.currentDirectoryURL = sourceRootURL
        process.arguments = [
            "-m", "ballontranslator",
            "--headless",
            "--exec_dirs", runDirectory.path,
            "--config_path", configURL.path,
            "--export-source-txt",
            "--export-translation-txt"
        ]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "PYTHONUNBUFFERED": "1",
            "QT_QPA_PLATFORM": "offscreen"
        ]) { _, new in new }
        process.standardInput = inputPipe
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        inputPipe.fileHandleForWriting.write(Data("exit\n".utf8))
        try? inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw BallonsTranslatorEngineError.processFailed(process.terminationStatus, String(log.suffix(1_200)))
        }
    }

    private func parseTranslation(
        projectURL: URL,
        sourceImageURL: URL,
        imageFingerprint: String,
        imageSize: CGSize
    ) throws -> PageTranslation {
        let project = try JSONDecoder().decode(BallonsProject.self, from: Data(contentsOf: projectURL))
        let ballonsBlocks = project.pages[Self.inputImageName] ?? []
        let refiner = KoreanTranslationRefiner()
        let blocks = ballonsBlocks.compactMap { block -> TextBlock? in
            guard block.xyxy.count == 4 else {
                return nil
            }
            let x1 = max(0, block.xyxy[0])
            let y1 = max(0, block.xyxy[1])
            let x2 = min(Double(imageSize.width), block.xyxy[2])
            let y2 = min(Double(imageSize.height), block.xyxy[3])
            guard x2 > x1, y2 > y1 else {
                return nil
            }

            let original = block.text.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let translated = (block.translation ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty || !translated.isEmpty else {
                return nil
            }
            let refined = refiner.refine(originalText: original, translatedText: translated)

            return TextBlock(
                box: TextBox(
                    x: x1 / Double(imageSize.width),
                    y: y1 / Double(imageSize.height),
                    width: (x2 - x1) / Double(imageSize.width),
                    height: (y2 - y1) / Double(imageSize.height)
                ),
                originalText: original,
                translatedText: refined,
                confidence: 1,
                sourceIsVertical: block.sourceIsVertical,
                detectedFontSize: block.detectedFontSize
            )
        }

        guard !blocks.isEmpty else {
            throw BallonsTranslatorEngineError.noTextBlocks
        }

        return PageTranslation(
            imageURL: sourceImageURL,
            imageFingerprint: imageFingerprint,
            sourceLanguage: .japanese,
            targetLanguage: .korean,
            blocks: blocks
        )
    }

    private func imageSize(for imageURL: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0,
              height > 0 else {
            throw BallonsTranslatorEngineError.invalidImageSize(imageURL)
        }
        return CGSize(width: width, height: height)
    }

    private func optionalFile(in directory: URL, suffix: String) -> URL? {
        let url = directory.appendingPathComponent("imgtrans_\(directory.lastPathComponent)\(suffix)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static let inputImageName = "001.png"

    private static var mangaOCRDevice: String {
        #if arch(arm64)
        "mps"
        #else
        "cpu"
        #endif
    }

    private static var inpaintDevice: String {
        #if arch(arm64)
        "mps"
        #else
        "cpu"
        #endif
    }

    private static func configJSON(enableTranslation: Bool) -> String {
        """
    {
      "module": {
        "textdetector": "ctd",
        "ocr": "manga_ocr",
        "inpainter": "lama_large_512px",
        "translator": "google",
        "enable_detect": true,
        "keep_exist_textlines": false,
        "filter_mask_by_bboxes": true,
        "enable_ocr": true,
        "enable_translate": \(enableTranslation ? "true" : "false"),
        "enable_inpaint": true,
        "ocr_font_detect": false,
        "textdetector_params": {
          "ctd": {
            "detect_size": 1280,
            "det_rearrange_max_batches": 4,
            "device": "cpu",
            "font size multiplier": 1.0,
            "font size max": -1,
            "font size min": -1,
            "mask dilate size": 2
          }
        },
        "ocr_params": {
          "manga_ocr": {
            "device": "\(mangaOCRDevice)"
          }
        },
        "translator_params": {
          "google": {
            "delay": 0.0
          }
        },
        "inpainter_params": {
          "lama_large_512px": {
            "inpaint_size": 1536,
            "device": "\(inpaintDevice)",
            "precision": "fp32"
          }
        },
        "translate_source": "日本語",
        "translate_target": "한국어",
        "translate_by_textblock": false,
        "check_need_inpaint": true,
        "empty_runcache": true,
        "finish_code": 15
      },
      "package_manager": {
        "auto_install_missing_packages": false,
        "installer_backend": "auto",
        "extra_install_args": ""
      },
      "display_lang": "ko_KR",
      "imgsave_quality": 100,
      "imgsave_ext": ".png",
      "intermediate_imgsave_ext": ".png"
    }
    """
    }
}

private struct BallonsProject: Decodable {
    let pages: [String: [BallonsBlock]]
}

private struct BallonsBlock: Decodable {
    let xyxy: [Double]
    let text: [String]
    let translation: String?
    let sourceIsVertical: Bool?
    let detectedFontSize: Double?

    private enum CodingKeys: String, CodingKey {
        case xyxy
        case text
        case translation
        case sourceIsVertical = "src_is_vertical"
        case detectedFontSize = "_detected_font_size"
    }
}
