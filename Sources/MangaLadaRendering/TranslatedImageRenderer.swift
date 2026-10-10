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
    case originalImageSizeMismatch
    case originalImageRequired
    case invalidOriginalBounds
    case textDoesNotFit(UUID, String)
    case overlappingRegions(UUID, UUID)

    public var errorDescription: String? {
        switch self {
        case .imageLoadFailed(let url):
            return "이미지를 불러올 수 없습니다: \(url.lastPathComponent)"
        case .noTranslationBlocks:
            return "저장할 번역 블록이 없습니다."
        case .pngEncodingFailed:
            return "PNG 이미지로 변환하지 못했습니다."
        case .originalImageSizeMismatch:
            return "원본과 글자 제거 이미지의 크기가 달라 원문을 복원할 수 없습니다. 원본을 다시 열어주세요."
        case .originalImageRequired:
            return "원문을 복원하려면 원본 이미지가 필요합니다. 원본을 다시 열어주세요."
        case .invalidOriginalBounds:
            return "원문 복원 영역이 이미지 밖에 있습니다. 영역을 다시 지정해주세요."
        case .textDoesNotFit(_, let text):
            return "말풍선에 문장이 들어가지 않습니다: ‘\(text.prefix(80))’. 문구 또는 인식 영역을 확인해주세요."
        case .overlappingRegions:
            return "인식한 대사 영역이 서로 겹칩니다. 원본에서 겹친 영역을 나누어 지정한 뒤 다시 적용해주세요."
        }
    }
}

@MainActor
public struct TranslatedImageRenderer {
    let typography: MangaTypography
    /// English dialogue is sized to its balloon; Japanese pages keep the established page-level size.
    let sourceLanguage: LanguageCode
    public init(typography: MangaTypography = MangaTypography(), sourceLanguage: LanguageCode = .japanese) {
        self.typography = typography; self.sourceLanguage = sourceLanguage
    }

    public func writePNG(
        sourceImageURL: URL,
        translation: PageTranslation,
        destinationURL: URL,
        fontScale: Double = 1.0,
        backgroundStyle: TranslationTextBackgroundStyle = .redactionBubble,
        originalImageURL: URL? = nil
    ) throws -> RenderedImageFile {
        guard let image = NSImage(contentsOf: sourceImageURL) else {
            throw TranslatedImageRenderError.imageLoadFailed(sourceImageURL)
        }

        let drawableBlocks = translation.blocks.filter { block in
            block.preservesOriginalArtwork || !displayText(for: block).isEmpty
        }
        guard !drawableBlocks.isEmpty else {
            throw TranslatedImageRenderError.noTranslationBlocks
        }

        var original: NSImage?
        let activeBlocks = drawableBlocks.filter { !$0.preservesOriginalArtwork }
        let keepsOriginal = activeBlocks.count != drawableBlocks.count
        let needsLettering = activeBlocks.contains {
            ($0.effectStyleID ?? ($0.textKind == .soundEffect ? typography.effectStyleID : nil)) == "automatic"
        }
        let needsPunctuation = !originalPunctuationRegions(in: drawableBlocks, imageSize: pixelBackedSize(for: image)).isEmpty
        if let originalImageURL = originalImageURL ?? (keepsOriginal ? translation.imageURL : nil),
           needsLettering || needsPunctuation || keepsOriginal {
            guard let loaded = NSImage(contentsOf: originalImageURL) else {
                throw TranslatedImageRenderError.imageLoadFailed(originalImageURL)
            }
            original = loaded
        }

        // The saved page states its own language; a caller's default renderer cannot resize it.
        let output = try TranslatedImageRenderer(typography: typography, sourceLanguage: translation.sourceLanguage).render(
            image: image,
            blocks: drawableBlocks,
            fontScale: fontScale,
            backgroundStyle: backgroundStyle,
            originalImage: original
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
        backgroundStyle: TranslationTextBackgroundStyle = .redactionBubble,
        originalImage: NSImage? = nil
    ) throws -> NSImage {
        try blocks.filter { !$0.preservesOriginalArtwork }.forEach { try LetteringPreferences.validate($0) }
        let size = pixelBackedSize(for: image)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw TranslatedImageRenderError.pngEncodingFailed }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context

        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )

        try restoreOriginalSelections(originalImage, blocks: blocks, imageSize: size)
        let preserved = try restoreOriginalPunctuation(originalImage, blocks: blocks, imageSize: size)

        let lightRegionDetector = LightRegionDetector(image: image, imageSize: size)
        let pageFontSize = DialogueTypesettingRules.pageFontSize(blocks: blocks, imageSize: size)
        let sourceLettering = originalImage.flatMap { SourceLettering(image: $0) }
        let containers = backgroundStyle == .none
            ? try balloonContainers(blocks: blocks, imageSize: size, detector: lightRegionDetector) : [:]
        for (index, block) in blocks.enumerated() where !block.preservesOriginalArtwork && !preserved.contains(index) {
            try draw(
                block: block,
                imageSize: size,
                fontScale: fontScale,
                pageFontSize: pageFontSize,
                backgroundStyle: backgroundStyle,
                balloonContainer: containers[block.id],
                sourceLettering: sourceLettering,
                lightRegionDetector: lightRegionDetector
            )
        }

        let output = NSImage(size: size)
        output.addRepresentation(bitmap)
        return output
    }

    func draw(
        block: TextBlock,
        imageSize: NSSize,
        fontScale: Double,
        pageFontSize: Double,
        backgroundStyle: TranslationTextBackgroundStyle,
        balloonContainer: BalloonShape?,
        sourceLettering: SourceLettering?,
        lightRegionDetector: LightRegionDetector?
    ) throws {
        let text = displayText(for: block)
        guard !text.isEmpty else {
            return
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if let offset = block.textOffset {
            let transform = NSAffineTransform()
            transform.translateX(by: offset.x * imageSize.width, yBy: -offset.y * imageSize.height)
            transform.concat()
        }

        let originalTextRect = pixelRect(for: block.textKind == .soundEffect ? LetteringPreferences.layoutBounds(for: block) : block.box, imageSize: imageSize)
        if block.textKind == .soundEffect {
            try SoundEffectRenderer.draw(block, in: originalTextRect, typography: typography, scale: fontScale, source: sourceLettering)
            return
        }
        if backgroundStyle == .none, block.textKind != .title {
            guard let balloonContainer else { throw TranslatedImageRenderError.textDoesNotFit(block.id, text) }
            try drawBalloon(block: block, text: text, imageSize: imageSize, pageFontSize: pageFontSize,
                            fontScale: fontScale, shape: balloonContainer, sourceLettering: sourceLettering, lightRegionDetector: lightRegionDetector)
            return
        }
        let flow = preferredTextFlow(for: originalTextRect, block: block, text: text)
        let fallbackRect = redactionRect(
            around: originalTextRect,
            imageSize: imageSize,
            text: text,
            flow: flow
        )
        let bubbleRect = textContainerRect(
            fallbackRect: fallbackRect,
            originalTextRect: originalTextRect,
            imageSize: imageSize,
            flow: flow,
            backgroundStyle: backgroundStyle,
            lightRegionDetector: lightRegionDetector
        ).integral
        let textRect = textDrawingRect(
            in: bubbleRect,
            originalTextRect: originalTextRect,
            flow: flow,
            sourceIsVertical: block.sourceIsVertical == true,
            lightRegionDetector: lightRegionDetector
        )
        let layout = fittedTextLayout(
            for: text,
            in: textRect,
            scale: fontScale * (block.fontScale ?? 1),
            flow: flow,
            detectedFontSize: block.detectedFontSize,
            backgroundStyle: backgroundStyle
        )
        let occupiedRect = occupiedTextRect(for: layout, in: textRect)
        let backingRect = textBackingRect(
            for: occupiedRect,
            in: bubbleRect,
            flow: flow,
            backgroundStyle: backgroundStyle
        )
        let radius = flow == .vertical
            ? min(backingRect.width, backingRect.height) * 0.42
            : min(18, min(backingRect.width, backingRect.height) * 0.22)
        let bubblePath = NSBezierPath(
            roundedRect: backingRect,
            xRadius: radius,
            yRadius: radius
        )

        switch backgroundStyle {
        case .redactionBubble:
            NSColor.white.setFill()
            bubblePath.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            bubblePath.lineWidth = 1
            bubblePath.stroke()
        case .readabilityBubble:
            NSColor.white.setFill()
            bubblePath.fill()
        case .none:
            break
        }

        draw(layout: layout, attributes: textAttributes(size: layout.fontSize, backgroundStyle: backgroundStyle,
                                                        decoratedTitle: block.textKind == .title), in: textRect)
    }

    func textAttributes(size: CGFloat, backgroundStyle: TranslationTextBackgroundStyle,
                        decoratedTitle: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: preferredTextFont(ofSize: size, backgroundStyle: backgroundStyle),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph
        ]
        if backgroundStyle == .none {
            attributes[.strokeColor] = NSColor.white.withAlphaComponent(decoratedTitle ? 1 : 0.64)
            attributes[.strokeWidth] = decoratedTitle ? -6.0 : -1.0
        }

        return attributes
    }

    func pngData(from image: NSImage) -> Data? {
        guard let bitmap = image.representations.first as? NSBitmapImageRep else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func displayText(for block: TextBlock) -> String {
        let translated = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translated.isEmpty {
            return translated
        }
        return block.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func attributedText(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        NSAttributedString(string: text, attributes: attributes)
    }
}
