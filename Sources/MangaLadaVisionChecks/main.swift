import AppKit
import Foundation
import MangaLadaCore
import MangaLadaVision

@main
struct MangaLadaVisionChecks {
    static func main() async throws {
        let service = VisionOCRService()
        if CommandLine.arguments.count > 1 {
            let blocks = try await service.recognizeText(in: URL(fileURLWithPath: CommandLine.arguments[1]), sourceLanguage: .japanese)
            print(String(decoding: try JSONEncoder().encode(blocks), as: UTF8.self))
            return
        }

        let japaneseURL = try makeSampleImage(text: "こんにちは 世界")
        let japaneseBlocks = try await service.recognizeText(in: japaneseURL, sourceLanguage: .japanese)
        try assertRecognition(
            blocks: japaneseBlocks,
            expectedTokens: ["こんにちは", "世界"],
            label: "Japanese"
        )

        let englishURL = try makeSampleImage(text: "HELLO WORLD")
        let englishBlocks = try await service.recognizeText(in: englishURL, sourceLanguage: .english)
        try assertRecognition(
            blocks: englishBlocks,
            expectedTokens: ["HELLO", "WORLD"],
            label: "English"
        )

        let japaneseRecognized = japaneseBlocks.map(\.originalText).joined(separator: " ")
        let englishRecognized = englishBlocks.map(\.originalText).joined(separator: " ")
        print("MangaLadaVisionChecks passed: ja=\(japaneseRecognized) en=\(englishRecognized)")
    }

    private static func assertRecognition(
        blocks: [TextBlock],
        expectedTokens: [String],
        label: String
    ) throws {
        guard !blocks.isEmpty else {
            throw CheckError.failed("Vision OCR did not recognize text in generated \(label) sample image.")
        }

        let recognized = blocks.map(\.originalText).joined(separator: " ").uppercased()
        let missingTokens = expectedTokens.filter { !recognized.contains($0.uppercased()) }
        guard missingTokens.isEmpty else {
            throw CheckError.failed("Vision OCR returned text, but missed expected \(label) tokens \(missingTokens): \(recognized)")
        }
    }

    private static func makeSampleImage(text: String) throws -> URL {
        let size = NSSize(width: 900, height: 320)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 78, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        let textRect = NSRect(x: 40, y: 98, width: 820, height: 120)
        text.draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckError.failed("Failed to render generated sample image.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaLadaVisionChecks")
            .appendingPathComponent(UUID().uuidString + ".png")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: outputURL, options: .atomic)
        return outputURL
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
