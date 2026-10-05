import AppKit
import Foundation
import MangaLadaCore
import MangaLadaRendering

@main
struct MangaLadaRenderingChecks {
    @MainActor
    static func main() throws {
        let root = try temporaryDirectory()
        stage("Explicit original regions")
        try checkOriginalRegions(in: root)
        stage("Original punctuation")
        try checkOriginalPunctuation(in: root)
        stage("Curved line wrapping")
        try checkCurvedLineWrapping()
        stage("Sound effects")
        try checkSoundEffects(in: root)
        stage("Dark captions and manual contours")
        try checkDarkCaptionAndManualContour()
        stage("PNG rendering and pixel preservation")
        let sourceURL = root.appendingPathComponent("source.png")
        let inpaintedSourceURL = root.appendingPathComponent("inpainted-source.png")
        let outputURL = root.appendingPathComponent("translated.png")
        let textOnlyOutputURL = root.appendingPathComponent("translated-text-only.png")
        let largeTextOnlyOutputURL = root.appendingPathComponent("translated-text-only-large.png")
        let readabilityOutputURL = root.appendingPathComponent("translated-readable.png")
        let koreanHorizontalOutputURL = root.appendingPathComponent("translated-korean-horizontal.png")
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

        var scalableTranslation = translation
        scalableTranslation.blocks = [translation.blocks[0]]
        _ = try TranslatedImageRenderer().writePNG(
            sourceImageURL: inpaintedSourceURL,
            translation: scalableTranslation,
            destinationURL: largeTextOnlyOutputURL,
            fontScale: 1.8,
            backgroundStyle: .none
        )
        guard let largeTextOnlyImage = NSImage(contentsOf: largeTextOnlyOutputURL) else {
            throw CheckError.failed("Scaled text-only PNG could not be loaded for inspection.")
        }
        let regularDarkPixels = darkPixelCount(
            image: textOnlyImage,
            normalizedArea: CGRect(x: 0.30, y: 0.38, width: 0.40, height: 0.18)
        )
        let largeDarkPixels = darkPixelCount(
            image: largeTextOnlyImage,
            normalizedArea: CGRect(x: 0.30, y: 0.38, width: 0.40, height: 0.18)
        )
        try require(
            largeDarkPixels > regularDarkPixels,
            "Font scale did not increase rendered text pixel coverage."
        )

        let verticalSourceKoreanTranslation = PageTranslation(
            imageURL: inpaintedSourceURL,
            imageFingerprint: "korean-horizontal-check",
            sourceLanguage: .japanese,
            targetLanguage: .korean,
            blocks: [
                TextBlock(
                    box: TextBox(x: 0.76, y: 0.12, width: 0.10, height: 0.58),
                    originalText: "僕の産まれてきた場所",
                    translatedText: "내가 태어난 곳",
                    confidence: 0.99,
                    sourceIsVertical: true,
                    detectedFontSize: 54
                )
            ]
        )
        _ = try TranslatedImageRenderer().writePNG(
            sourceImageURL: inpaintedSourceURL,
            translation: verticalSourceKoreanTranslation,
            destinationURL: koreanHorizontalOutputURL,
            backgroundStyle: .none
        )
        guard let koreanHorizontalImage = NSImage(contentsOf: koreanHorizontalOutputURL) else {
            throw CheckError.failed("Korean horizontal PNG could not be loaded for inspection.")
        }
        guard let koreanBounds = darkPixelBounds(
            image: koreanHorizontalImage,
            normalizedArea: CGRect(x: 0.72, y: 0.12, width: 0.20, height: 0.60)
        ) else {
            throw CheckError.failed("Korean vertical-source translation area appears blank.")
        }
        try require(
            koreanBounds.width >= 48,
            "Korean translation was laid out as narrow vertical characters."
        )

        let readabilityResult = try TranslatedImageRenderer().writePNG(
            sourceImageURL: inpaintedSourceURL,
            translation: translation,
            destinationURL: readabilityOutputURL,
            backgroundStyle: .readabilityBubble
        )
        try require(readabilityResult.blockCount == 2, "Readability renderer wrote wrong block count.")
        guard let readabilityImage = NSImage(contentsOf: readabilityOutputURL) else {
            throw CheckError.failed("Readability PNG could not be loaded for inspection.")
        }
        try require(
            containsPalePixel(image: readabilityImage, normalizedArea: CGRect(x: 0.75, y: 0.16, width: 0.12, height: 0.50)),
            "Readability renderer did not add a light backing behind text."
        )
        try require(
            containsTintedPixel(image: readabilityImage, normalizedArea: CGRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10)),
            "Readability renderer unexpectedly replaced untouched background."
        )
        stage("Short vertical source")
        try checkShortVerticalSource(in: root)
        stage("Shape and consistency")
        try checkShapeAndConsistency(in: root)
        stage("Floating text")
        try checkFloatingText()
        stage("Adjacent balloons")
        try checkAdjacentBalloons(in: root)
        print("MangaLadaRenderingChecks passed: \(outputURL.path)")
    }

    static func stage(_ message: String) {
        FileHandle.standardError.write(Data("Rendering check: \(message)\n".utf8))
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
        darkPixelCount(image: image, normalizedArea: normalizedArea) > 0
    }

    private static func darkPixelCount(image: NSImage, normalizedArea: CGRect) -> Int {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return 0
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

        var count = 0
        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                if color.redComponent < 0.35,
                   color.greenComponent < 0.35,
                   color.blueComponent < 0.35 {
                    count += 1
                }
            }
        }

        return count
    }

    static func darkPixelBounds(image: NSImage, normalizedArea: CGRect) -> CGRect? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
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

        var darkMinX = Int.max
        var darkMinY = Int.max
        var darkMaxX = Int.min
        var darkMaxY = Int.min
        for y in minY...maxY {
            for x in minX...maxX {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }

                if color.redComponent < 0.35,
                   color.greenComponent < 0.35,
                   color.blueComponent < 0.35 {
                    darkMinX = min(darkMinX, x)
                    darkMinY = min(darkMinY, y)
                    darkMaxX = max(darkMaxX, x)
                    darkMaxY = max(darkMaxY, y)
                }
            }
        }

        guard darkMinX <= darkMaxX, darkMinY <= darkMaxY else {
            return nil
        }
        return CGRect(
            x: darkMinX,
            y: darkMinY,
            width: darkMaxX - darkMinX + 1,
            height: darkMaxY - darkMinY + 1
        )
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

    private static func containsPalePixel(image: NSImage, normalizedArea: CGRect) -> Bool {
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

                if color.redComponent > 0.95,
                   color.greenComponent > 0.95,
                   color.blueComponent > 0.95 {
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

    static func require(_ condition: Bool, _ message: String) throws {
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
