import AppKit
import Foundation
import MangaLadaCore
import MangaLadaRendering

@main
struct MangaLadaRenderingChecks {
    @MainActor
    static func main() throws {
        let root = try temporaryDirectory()
        let sourceURL = root.appendingPathComponent("source.png")
        let inpaintedSourceURL = root.appendingPathComponent("inpainted-source.png")
        let outputURL = root.appendingPathComponent("translated.png")
        let textOnlyOutputURL = root.appendingPathComponent("translated-text-only.png")
        try makeSourceImage(at: sourceURL)
        try makeInpaintedSourceImage(at: inpaintedSourceURL)

        let translation = PageTranslation(
            imageURL: sourceURL,
            imageFingerprint: "render-check",
            sourceLanguage: .japanese,
            targetLanguage: .korean,
            blocks: [
                TextBlock(
                    box: TextBox(x: 0.22, y: 0.34, width: 0.56, height: 0.24),
                    originalText: "こんにちは 世界",
                    translatedText: "안녕하세요 세상",
                    confidence: 0.99
                ),
                TextBlock(
                    box: TextBox(x: 0.76, y: 0.12, width: 0.10, height: 0.58),
                    originalText: "縦書きの長い台詞",
                    translatedText: "긴 한국어 문장을 좁은 세로 말풍선 안에 읽기 좋게 배치합니다",
                    confidence: 0.98
                )
            ]
        )

        let result = try TranslatedImageRenderer().writePNG(
            sourceImageURL: sourceURL,
            translation: translation,
            destinationURL: outputURL
        )

        try require(result.blockCount == 2, "Renderer wrote wrong block count.")
        let outputData = try Data(contentsOf: outputURL)
        try require(outputData.count > 10_000, "Rendered PNG is unexpectedly small.")

        guard let outputImage = NSImage(contentsOf: outputURL) else {
            throw CheckError.failed("Rendered PNG could not be loaded for inspection.")
        }

        try require(
            containsDarkPixel(image: outputImage, normalizedArea: CGRect(x: 0.30, y: 0.38, width: 0.40, height: 0.18)),
            "Rendered translation area appears blank."
        )
        try require(
            !containsDarkPixel(image: outputImage, normalizedArea: CGRect(x: 0.25, y: 0.43, width: 0.08, height: 0.12)),
            "Original text still appears through the redacted area."
        )

        let textOnlyResult = try TranslatedImageRenderer().writePNG(
            sourceImageURL: inpaintedSourceURL,
            translation: translation,
            destinationURL: textOnlyOutputURL,
            backgroundStyle: .none
        )
        try require(textOnlyResult.blockCount == 2, "Text-only renderer wrote wrong block count.")
        guard let textOnlyImage = NSImage(contentsOf: textOnlyOutputURL) else {
            throw CheckError.failed("Text-only PNG could not be loaded for inspection.")
        }
        try require(
            containsDarkPixel(image: textOnlyImage, normalizedArea: CGRect(x: 0.30, y: 0.38, width: 0.40, height: 0.18)),
            "Text-only translation area appears blank."
        )
        try require(
            containsDarkPixel(image: textOnlyImage, normalizedArea: CGRect(x: 0.75, y: 0.16, width: 0.12, height: 0.50)),
            "Narrow vertical translation area appears blank."
        )
        try require(
            containsTintedPixel(image: textOnlyImage, normalizedArea: CGRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10)),
            "Text-only renderer unexpectedly replaced untouched background."
        )
        print("MangaLadaRenderingChecks passed: \(outputURL.path)")
    }

    private static func makeSourceImage(at url: URL) throws {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 110, y: 120, width: 420, height: 120), xRadius: 28, yRadius: 28).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 54, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        "こんにちは 世界".draw(in: NSRect(x: 120, y: 152, width: 400, height: 70), withAttributes: attributes)
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckError.failed("Failed to create source PNG.")
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: url, options: .atomic)
    }

    private static func makeInpaintedSourceImage(at url: URL) throws {
        let size = NSSize(width: 640, height: 360)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(calibratedWhite: 0.95, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 110, y: 120, width: 420, height: 120), xRadius: 28, yRadius: 28).fill()
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckError.failed("Failed to create inpainted source PNG.")
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: url, options: .atomic)
    }

    private static func containsDarkPixel(image: NSImage, normalizedArea: CGRect) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return false
        }

        let area = NSRect(
            x: normalizedArea.minX * Double(bitmap.pixelsWide),
            y: normalizedArea.minY * Double(bitmap.pixelsHigh),
            width: normalizedArea.width * Double(bitmap.pixelsWide),
            height: normalizedArea.height * Double(bitmap.pixelsHigh)
        )
        let minX = max(0, Int(area.minX))
        let maxX = min(bitmap.pixelsWide - 1, Int(area.maxX))
        let minY = max(0, Int(area.minY))
        let maxY = min(bitmap.pixelsHigh - 1, Int(area.maxY))

        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                if color.redComponent < 0.35,
                   color.greenComponent < 0.35,
                   color.blueComponent < 0.35 {
                    return true
                }
            }
        }

        return false
    }

    private static func containsTintedPixel(image: NSImage, normalizedArea: CGRect) -> Bool {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return false
        }

        let area = NSRect(
            x: normalizedArea.minX * Double(bitmap.pixelsWide),
            y: normalizedArea.minY * Double(bitmap.pixelsHigh),
            width: normalizedArea.width * Double(bitmap.pixelsWide),
            height: normalizedArea.height * Double(bitmap.pixelsHigh)
        )
        let minX = max(0, Int(area.minX))
        let maxX = min(bitmap.pixelsWide - 1, Int(area.maxX))
        let minY = max(0, Int(area.minY))
        let maxY = min(bitmap.pixelsHigh - 1, Int(area.maxY))

        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                if color.blueComponent > color.redComponent,
                   color.blueComponent > 0.75,
                   color.redComponent > 0.70 {
                    return true
                }
            }
        }

        return false
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaLadaRenderingChecks")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw CheckError.failed(message)
        }
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
