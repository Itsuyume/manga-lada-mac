import AppKit
import Foundation
import MangaLadaVision

@main
struct MangaLadaVisionChecks {
    static func main() async throws {
        let sampleURL = try makeSampleImage()
        let blocks = try await VisionOCRService().recognizeText(in: sampleURL)

        guard !blocks.isEmpty else {
            throw CheckError.failed("Vision OCR did not recognize text in generated sample image.")
        }

        let recognized = blocks.map(\.originalText).joined(separator: " ")
        guard recognized.contains("こんにちは") || recognized.contains("世界") else {
            throw CheckError.failed("Vision OCR returned text, but not the expected Japanese sample: \(recognized)")
        }

        print("MangaLadaVisionChecks passed: \(recognized)")
    }

    private static func makeSampleImage() throws -> URL {
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
        "こんにちは 世界".draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckError.failed("Failed to render generated sample image.")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaLadaVisionChecks")
            .appendingPathComponent("sample.png")
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
