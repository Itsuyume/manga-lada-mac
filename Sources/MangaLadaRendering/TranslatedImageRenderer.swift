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

        if backgroundStyle == .redactionBubble {
            NSColor.white.setFill()
            bubblePath.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            bubblePath.lineWidth = 1
            bubblePath.stroke()
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        let fontSize = fittedFontSize(for: text, in: bubbleRect, scale: fontScale)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: preferredTextFont(ofSize: fontSize, backgroundStyle: backgroundStyle),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]

        let textRect = bubbleRect.insetBy(dx: max(6, bubbleRect.width * 0.03), dy: max(4, bubbleRect.height * 0.08))
        attributedText(text, attributes: attributes).draw(in: verticallyCenteredTextRect(
            text,
            attributes: attributes,
            bounds: textRect
        ))
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

    private func fittedFontSize(for text: String, in rect: NSRect, scale: Double) -> CGFloat {
        let width = max(1, rect.width - 12)
        let height = max(1, rect.height - 8)
        let explicitLineCount = max(1, text.components(separatedBy: .newlines).count)
        let narrowVerticalBox = rect.width < rect.height * 0.75
        let geometryLimit = narrowVerticalBox ? rect.width * 0.20 : min(rect.height * 0.34, 42)
        let lineHeightLimit = height / CGFloat(explicitLineCount) * 0.68
        let maxSize = min(max(geometryLimit, 10), lineHeightLimit, 34) * scale
        let minSize: CGFloat = 8

        var size = maxSize
        while size > minSize {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold)
            ]
            let measured = attributedText(text, attributes: attributes).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            if measured.height <= height && measured.width <= width {
                return size
            }
            size -= 1
        }

        return minSize
    }

    private func preferredTextFont(ofSize size: CGFloat, backgroundStyle: TranslationTextBackgroundStyle) -> NSFont {
        let fontName = backgroundStyle == .none ? "AppleSDGothicNeo-Medium" : "AppleSDGothicNeo-SemiBold"
        let fallbackWeight: NSFont.Weight = backgroundStyle == .none ? .medium : .semibold
        return NSFont(name: fontName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: fallbackWeight)
    }

    private func verticallyCenteredTextRect(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        bounds: NSRect
    ) -> NSRect {
        let measured = attributedText(text, attributes: attributes).boundingRect(
            with: NSSize(width: bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let y = bounds.midY - measured.height / 2
        return NSRect(x: bounds.minX, y: y, width: bounds.width, height: min(bounds.height, measured.height + 2))
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
