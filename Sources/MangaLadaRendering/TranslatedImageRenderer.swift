import AppKit
import Foundation
import MangaLadaCore

public struct RenderedImageFile: Equatable, Sendable {
    public let url: URL
    public let blockCount: Int

    public init(url: URL, blockCount: Int) {
        self.url = url
        self.blockCount = blockCount
    }
}

public enum TranslationTextBackgroundStyle: Equatable, Sendable {
    case redactionBubble
    case readabilityBubble
    case none
}

public enum TranslatedImageRenderError: LocalizedError, Equatable {
    case imageLoadFailed(URL)
    case noTranslationBlocks
    case pngEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let url):
            return "이미지를 불러올 수 없습니다: \(url.lastPathComponent)"
        case .noTranslationBlocks:
            return "저장할 번역 블록이 없습니다."
        case .pngEncodingFailed:
            return "PNG 이미지로 변환하지 못했습니다."
        }
    }
}

@MainActor
public struct TranslatedImageRenderer {
    public init() {}

    public func writePNG(
        sourceImageURL: URL,
        translation: PageTranslation,
        destinationURL: URL,
        fontScale: Double = 1.0,
        backgroundStyle: TranslationTextBackgroundStyle = .redactionBubble
    ) throws -> RenderedImageFile {
        guard let image = NSImage(contentsOf: sourceImageURL) else {
            throw TranslatedImageRenderError.imageLoadFailed(sourceImageURL)
        }

        let drawableBlocks = translation.blocks.filter { block in
            !displayText(for: block).isEmpty
        }
        guard !drawableBlocks.isEmpty else {
            throw TranslatedImageRenderError.noTranslationBlocks
        }

        let output = render(
            image: image,
            blocks: drawableBlocks,
            fontScale: fontScale,
            backgroundStyle: backgroundStyle
        )
        guard let pngData = pngData(from: output) else {
            throw TranslatedImageRenderError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try pngData.write(to: destinationURL, options: .atomic)
        return RenderedImageFile(url: destinationURL, blockCount: drawableBlocks.count)
    }

    public func render(
        image: NSImage,
        blocks: [TextBlock],
        fontScale: Double = 1.0,
        backgroundStyle: TranslationTextBackgroundStyle = .redactionBubble
    ) -> NSImage {
        let size = pixelBackedSize(for: image)
        let output = NSImage(size: size)

        output.lockFocus()
        defer { output.unlockFocus() }

        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        for block in blocks {
            draw(block: block, imageSize: size, fontScale: fontScale, backgroundStyle: backgroundStyle)
        }

        return output
    }

    private func draw(
        block: TextBlock,
        imageSize: NSSize,
        fontScale: Double,
        backgroundStyle: TranslationTextBackgroundStyle
    ) {
        let text = displayText(for: block)
        guard !text.isEmpty else {
            return
        }

        let originalTextRect = pixelRect(for: block.box, imageSize: imageSize)
        let bubbleRect = redactionRect(around: originalTextRect).integral
        let bubblePath = NSBezierPath(
            roundedRect: bubbleRect,
            xRadius: min(10, bubbleRect.height * 0.18),
            yRadius: min(10, bubbleRect.height * 0.18)
        )

        switch backgroundStyle {
        case .redactionBubble:
            NSColor.white.setFill()
            bubblePath.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            bubblePath.lineWidth = 1
            bubblePath.stroke()
        case .readabilityBubble:
            NSColor.white.withAlphaComponent(0.86).setFill()
            bubblePath.fill()
            NSColor.black.withAlphaComponent(0.14).setStroke()
            bubblePath.lineWidth = 1
            bubblePath.stroke()
        case .none:
            break
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let textRect = bubbleRect.insetBy(dx: max(6, bubbleRect.width * 0.03), dy: max(4, bubbleRect.height * 0.08))
        let layout = fittedTextLayout(
            for: text,
            in: textRect,
            scale: fontScale,
            backgroundStyle: backgroundStyle
        )
        var attributes: [NSAttributedString.Key: Any] = [
            .font: preferredTextFont(ofSize: layout.fontSize, backgroundStyle: backgroundStyle),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        if backgroundStyle == .none {
            attributes[.strokeColor] = NSColor.white.withAlphaComponent(0.64)
            attributes[.strokeWidth] = -1.0
        }

        draw(layout: layout, attributes: attributes, in: textRect)
    }

    private func pixelBackedSize(for image: NSImage) -> NSSize {
        if let representation = image.representations.first {
            let width = representation.pixelsWide > 0 ? representation.pixelsWide : Int(image.size.width)
            let height = representation.pixelsHigh > 0 ? representation.pixelsHigh : Int(image.size.height)
            return NSSize(width: width, height: height)
        }
        return image.size
    }

    private func pixelRect(for box: TextBox, imageSize: NSSize) -> NSRect {
        let x = box.x * imageSize.width
        let yFromTop = box.y * imageSize.height
        let width = max(1, box.width * imageSize.width)
        let height = max(1, box.height * imageSize.height)
        return NSRect(x: x, y: imageSize.height - yFromTop - height, width: width, height: height)
    }

    private func redactionRect(around rect: NSRect) -> NSRect {
        let horizontalPadding = max(10, rect.width * 0.08)
        let verticalPadding = max(6, rect.height * 0.16)
        return rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private func fittedTextLayout(
        for text: String,
        in rect: NSRect,
        scale: Double,
        backgroundStyle: TranslationTextBackgroundStyle
    ) -> TextLayout {
        let width = max(1, rect.width - 12)
        let height = max(1, rect.height - 8)
        let normalizedText = normalizedRenderableText(text)
        let narrowVerticalBox = rect.width < rect.height * 0.70
        let geometryLimit = narrowVerticalBox ? rect.width * 0.34 : min(rect.height * 0.36, 42)
        let maxSize = min(max(geometryLimit, 13), 38) * scale
        let minSize: CGFloat = backgroundStyle == .none ? 10 : 8

        var size = maxSize
        while size > minSize {
            let font = preferredTextFont(ofSize: size, backgroundStyle: backgroundStyle)
            let lines = wrappedLines(for: normalizedText, maxWidth: width, font: font)
            let lineHeight = ceil(size * 1.16)
            let measuredHeight = CGFloat(lines.count) * lineHeight
            if !lines.isEmpty,
               measuredHeight <= height,
               lines.allSatisfy({ measuredWidth($0, font: font) <= width }) {
                return TextLayout(lines: lines, fontSize: size, lineHeight: lineHeight)
            }
            size -= 1
        }

        let font = preferredTextFont(ofSize: minSize, backgroundStyle: backgroundStyle)
        return TextLayout(
            lines: wrappedLines(for: normalizedText, maxWidth: width, font: font),
            fontSize: minSize,
            lineHeight: ceil(minSize * 1.16)
        )
    }

    private func preferredTextFont(ofSize size: CGFloat, backgroundStyle: TranslationTextBackgroundStyle) -> NSFont {
        let fontName = backgroundStyle == .none ? "AppleSDGothicNeo-Medium" : "AppleSDGothicNeo-SemiBold"
        let fallbackWeight: NSFont.Weight = backgroundStyle == .none ? .medium : .semibold
        return NSFont(name: fontName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: fallbackWeight)
    }

    private func draw(
        layout: TextLayout,
        attributes: [NSAttributedString.Key: Any],
        in bounds: NSRect
    ) {
        let totalHeight = CGFloat(layout.lines.count) * layout.lineHeight
        let topY = bounds.midY + totalHeight / 2

        for (index, line) in layout.lines.enumerated() {
            let lineRect = NSRect(
                x: bounds.minX,
                y: topY - CGFloat(index + 1) * layout.lineHeight,
                width: bounds.width,
                height: layout.lineHeight
            )
            attributedText(line, attributes: attributes).draw(in: lineRect)
        }
    }

    private func normalizedRenderableText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ([,.!?…])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wrappedLines(for text: String, maxWidth: CGFloat, font: NSFont) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return []
        }

        var lines: [String] = []
        var current = ""

        for word in words {
            let candidate = current.isEmpty ? word : "\(current) \(word)"
            if measuredWidth(candidate, font: font) <= maxWidth {
                current = candidate
                continue
            }

            if !current.isEmpty {
                lines.append(current)
            }

            if measuredWidth(word, font: font) <= maxWidth {
                current = word
            } else {
                let splitLines = splitLongWord(word, maxWidth: maxWidth, font: font)
                lines.append(contentsOf: splitLines.dropLast())
                current = splitLines.last ?? ""
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private func splitLongWord(_ word: String, maxWidth: CGFloat, font: NSFont) -> [String] {
        var lines: [String] = []
        var current = ""

        for character in word {
            let candidate = current + String(character)
            if candidate.count > 1, measuredWidth(candidate, font: font) > maxWidth {
                lines.append(current)
                current = String(character)
            } else {
                current = candidate
            }
        }

        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }

    private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        attributedText(text, attributes: [.font: font]).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func displayText(for block: TextBlock) -> String {
        let translated = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translated.isEmpty {
            return translated
        }
        return block.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func attributedText(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: text, attributes: attributes)
    }
}

private struct TextLayout {
    let lines: [String]
    let fontSize: CGFloat
    let lineHeight: CGFloat
}
