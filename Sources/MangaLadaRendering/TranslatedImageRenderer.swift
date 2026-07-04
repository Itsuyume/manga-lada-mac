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

        let lightRegionDetector = LightRegionDetector(image: image, imageSize: size)
        for block in blocks {
            draw(
                block: block,
                imageSize: size,
                fontScale: fontScale,
                backgroundStyle: backgroundStyle,
                lightRegionDetector: lightRegionDetector
            )
        }

        return output
    }

    private func draw(
        block: TextBlock,
        imageSize: NSSize,
        fontScale: Double,
        backgroundStyle: TranslationTextBackgroundStyle,
        lightRegionDetector: LightRegionDetector?
    ) {
        let text = displayText(for: block)
        guard !text.isEmpty else {
            return
        }

        let originalTextRect = pixelRect(for: block.box, imageSize: imageSize)
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
        let radius = flow == .vertical
            ? min(bubbleRect.width, bubbleRect.height) * 0.42
            : min(18, min(bubbleRect.width, bubbleRect.height) * 0.22)
        let bubblePath = NSBezierPath(
            roundedRect: bubbleRect,
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
            scale: fontScale,
            flow: flow,
            detectedFontSize: block.detectedFontSize,
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

    private func textDrawingRect(
        in bubbleRect: NSRect,
        originalTextRect: NSRect,
        flow: TextFlow,
        sourceIsVertical: Bool,
        lightRegionDetector: LightRegionDetector?
    ) -> NSRect {
        let baseRect = bubbleRect.insetBy(
            dx: flow == .vertical ? max(4, bubbleRect.width * 0.10) : max(6, bubbleRect.width * 0.05),
            dy: flow == .vertical ? max(6, bubbleRect.height * 0.05) : max(5, bubbleRect.height * 0.07)
        )
        guard flow == .horizontal,
              sourceIsVertical,
              bubbleRect.height >= bubbleRect.width * 1.12 else {
            return baseRect
        }

        let columnWidth = min(
            baseRect.width,
            max(96, min(originalTextRect.width * 0.70, bubbleRect.width * 0.44))
        )
        let minX = bestLightColumnX(
            in: baseRect,
            columnWidth: columnWidth,
            lightRegionDetector: lightRegionDetector
        ) ?? max(baseRect.minX, min(baseRect.maxX - columnWidth, bubbleRect.midX - columnWidth / 2))
        return NSRect(
            x: minX,
            y: baseRect.minY,
            width: columnWidth,
            height: baseRect.height
        )
    }

    private func bestLightColumnX(
        in baseRect: NSRect,
        columnWidth: CGFloat,
        lightRegionDetector: LightRegionDetector?
    ) -> CGFloat? {
        guard let lightRegionDetector,
              baseRect.width > columnWidth + 1 else {
            return nil
        }

        let steps = 14
        var bestX = baseRect.minX
        var bestScore = -Double.greatestFiniteMagnitude
        for step in 0...steps {
            let progress = CGFloat(step) / CGFloat(steps)
            let x = baseRect.minX + (baseRect.width - columnWidth) * progress
            let candidate = NSRect(x: x, y: baseRect.minY, width: columnWidth, height: baseRect.height)
            let centerPenalty = Double(abs(candidate.midX - baseRect.midX) / max(1, baseRect.width)) * 0.08
            let score = lightRegionDetector.lightCoverage(in: candidate) - centerPenalty
            if score > bestScore {
                bestScore = score
                bestX = x
            }
        }
        return bestScore >= 0.42 ? bestX : nil
    }

    private func textContainerRect(
        fallbackRect: NSRect,
        originalTextRect: NSRect,
        imageSize: NSSize,
        flow: TextFlow,
        backgroundStyle: TranslationTextBackgroundStyle,
        lightRegionDetector: LightRegionDetector?
    ) -> NSRect {
        guard backgroundStyle == .none,
              let detectedRect = lightRegionDetector?.connectedLightRegion(
                around: originalTextRect,
                imageSize: imageSize,
                flow: flow
              ) else {
            return fallbackRect
        }

        let mergedRect = detectedRect.union(originalTextRect)
        guard mergedRect.width >= fallbackRect.width * 0.72,
              mergedRect.height >= fallbackRect.height * 0.72 else {
            return fallbackRect
        }
        return clamped(mergedRect, imageSize: imageSize)
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

    private func redactionRect(
        around rect: NSRect,
        imageSize: NSSize,
        text: String,
        flow: TextFlow
    ) -> NSRect {
        let characterCount = CGFloat(max(0, normalizedRenderableText(text).filter { !$0.isWhitespace }.count))
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        switch flow {
        case .vertical:
            horizontalPadding = max(10, rect.width * min(0.24, 0.12 + characterCount * 0.004))
            verticalPadding = max(8, rect.height * 0.08)
        case .horizontal:
            horizontalPadding = max(10, rect.width * min(0.26, 0.10 + characterCount * 0.004))
            verticalPadding = max(7, rect.height * min(0.18, 0.08 + characterCount * 0.002))
        }
        let padded = rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
        return clamped(padded, imageSize: imageSize)
    }

    private func clamped(_ rect: NSRect, imageSize: NSSize) -> NSRect {
        let minX = max(0, rect.minX)
        let minY = max(0, rect.minY)
        let maxX = min(imageSize.width, rect.maxX)
        let maxY = min(imageSize.height, rect.maxY)
        return NSRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }

    private func preferredTextFlow(for rect: NSRect, block: TextBlock, text: String) -> TextFlow {
        let normalizedText = normalizedRenderableText(text)
        let characterCount = normalizedText.filter { !$0.isWhitespace }.count
        let tallNarrowBox = rect.height >= rect.width * 2.05
        let veryShortText = characterCount <= 8
        if block.sourceIsVertical == true, tallNarrowBox, veryShortText {
            return .vertical
        }
        return tallNarrowBox && veryShortText ? .vertical : .horizontal
    }

    private func fittedTextLayout(
        for text: String,
        in rect: NSRect,
        scale: Double,
        flow: TextFlow,
        detectedFontSize: Double?,
        backgroundStyle: TranslationTextBackgroundStyle
    ) -> TextLayout {
        switch flow {
        case .vertical:
            return fittedVerticalTextLayout(
                for: text,
                in: rect,
                scale: scale,
                detectedFontSize: detectedFontSize,
                backgroundStyle: backgroundStyle
            )
        case .horizontal:
            return fittedHorizontalTextLayout(
                for: text,
                in: rect,
                scale: scale,
                detectedFontSize: detectedFontSize,
                backgroundStyle: backgroundStyle
            )
        }
    }

    private func fittedHorizontalTextLayout(
        for text: String,
        in rect: NSRect,
        scale: Double,
        detectedFontSize: Double?,
        backgroundStyle: TranslationTextBackgroundStyle
    ) -> TextLayout {
        let width = max(1, rect.width - 12)
        let height = max(1, rect.height - 8)
        let normalizedText = normalizedRenderableText(text)
        let geometryLimit = min(rect.height * 0.42, rect.width * 0.22)
        let sourceLimit = detectedFontSize.map { CGFloat($0) * 0.92 } ?? geometryLimit
        let maxSize = min(max(geometryLimit, sourceLimit, 16), 112) * scale
        let minimumBase = max(backgroundStyle == .none ? 10 : 13, min(rect.width, rect.height) * 0.10)
        let minSize = max(8, min(max(minimumBase * scale, 11), 28))

        var size = maxSize
        while size >= minSize {
            let font = preferredTextFont(ofSize: size, backgroundStyle: backgroundStyle)
            let lines = wrappedLines(for: normalizedText, maxWidth: width, font: font)
            let lineHeight = ceil(size * 1.06)
            let measuredHeight = CGFloat(lines.count) * lineHeight
            if !lines.isEmpty,
               measuredHeight <= height,
               lines.allSatisfy({ measuredWidth($0, font: font) <= width }) {
                return .horizontal(lines: lines, fontSize: size, lineHeight: lineHeight)
            }
            size -= 1
        }

        let hardMinSize = max(7, minSize * 0.72)
        var fallbackSize = minSize - 1
        while fallbackSize >= hardMinSize {
            let font = preferredTextFont(ofSize: fallbackSize, backgroundStyle: backgroundStyle)
            let lines = wrappedLines(for: normalizedText, maxWidth: width, font: font)
            let lineHeight = ceil(fallbackSize * 1.06)
            let measuredHeight = CGFloat(lines.count) * lineHeight
            if !lines.isEmpty,
               measuredHeight <= height,
               lines.allSatisfy({ measuredWidth($0, font: font) <= width }) {
                return .horizontal(lines: lines, fontSize: fallbackSize, lineHeight: lineHeight)
            }
            fallbackSize -= 1
        }

        let font = preferredTextFont(ofSize: hardMinSize, backgroundStyle: backgroundStyle)
        return .horizontal(
            lines: wrappedLines(for: normalizedText, maxWidth: width, font: font),
            fontSize: hardMinSize,
            lineHeight: ceil(hardMinSize * 1.06)
        )
    }

    private func fittedVerticalTextLayout(
        for text: String,
        in rect: NSRect,
        scale: Double,
        detectedFontSize: Double?,
        backgroundStyle: TranslationTextBackgroundStyle
    ) -> TextLayout {
        let units = verticalTextUnits(for: text)
        let width = max(1, rect.width - 4)
        let height = max(1, rect.height - 4)
        let geometryLimit = min(rect.width * 0.52, rect.height * 0.16)
        let sourceLimit = detectedFontSize.map { CGFloat($0) * 0.78 } ?? geometryLimit
        let maxSize = min(max(geometryLimit, sourceLimit, 16), 96) * scale
        let minimumBase = max(backgroundStyle == .none ? 10 : 13, min(rect.width, rect.height) * 0.12)
        let minSize = max(8, min(max(minimumBase * scale, 11), 28))

        var size = maxSize
        while size >= minSize {
            let lineHeight = ceil(size * 1.08)
            let columnWidth = ceil(size * 1.18)
            let maxRows = max(1, Int(floor(height / lineHeight)))
            let columns = verticalColumns(for: units, maxRows: maxRows)
            if !columns.isEmpty,
               CGFloat(columns.count) * columnWidth <= width {
                return .vertical(
                    columns: columns,
                    fontSize: size,
                    lineHeight: lineHeight,
                    columnWidth: columnWidth
                )
            }
            size -= 1
        }

        let hardMinSize = max(7, minSize * 0.72)
        let lineHeight = ceil(hardMinSize * 1.08)
        let columnWidth = ceil(hardMinSize * 1.18)
        return .vertical(
            columns: verticalColumns(for: units, maxRows: max(1, Int(floor(height / lineHeight)))),
            fontSize: hardMinSize,
            lineHeight: lineHeight,
            columnWidth: columnWidth
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
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).setClip()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }

        switch layout {
        case .horizontal(let lines, _, let lineHeight):
            drawHorizontal(lines: lines, lineHeight: lineHeight, attributes: attributes, in: bounds)
        case .vertical(let columns, _, let lineHeight, let columnWidth):
            drawVertical(columns: columns, lineHeight: lineHeight, columnWidth: columnWidth, attributes: attributes, in: bounds)
        }
    }

    private func drawHorizontal(
        lines: [String],
        lineHeight: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        in bounds: NSRect
    ) {
        let totalHeight = CGFloat(lines.count) * lineHeight
        let topY = bounds.midY + totalHeight / 2

        for (index, line) in lines.enumerated() {
            let lineRect = NSRect(
                x: bounds.minX,
                y: topY - CGFloat(index + 1) * lineHeight,
                width: bounds.width,
                height: lineHeight
            )
            attributedText(line, attributes: attributes).draw(in: lineRect)
        }
    }

    private func drawVertical(
        columns: [[String]],
        lineHeight: CGFloat,
        columnWidth: CGFloat,
        attributes: [NSAttributedString.Key: Any],
        in bounds: NSRect
    ) {
        let totalWidth = CGFloat(columns.count) * columnWidth
        let rightX = bounds.midX + totalWidth / 2

        for (columnIndex, column) in columns.enumerated() {
            let x = rightX - CGFloat(columnIndex + 1) * columnWidth
            let totalHeight = CGFloat(column.count) * lineHeight
            let topY = bounds.midY + totalHeight / 2

            for (rowIndex, unit) in column.enumerated() {
                let unitRect = NSRect(
                    x: x,
                    y: topY - CGFloat(rowIndex + 1) * lineHeight,
                    width: columnWidth,
                    height: lineHeight
                )
                attributedText(unit, attributes: attributes).draw(in: unitRect)
            }
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

    private func verticalTextUnits(for text: String) -> [String] {
        normalizedRenderableText(text)
            .filter { !$0.isWhitespace }
            .map { String($0) }
    }

    private func verticalColumns(for units: [String], maxRows: Int) -> [[String]] {
        guard maxRows > 0 else {
            return []
        }
        return stride(from: 0, to: units.count, by: maxRows).map { start in
            Array(units[start..<min(start + maxRows, units.count)])
        }
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

enum TextFlow {
    case horizontal
    case vertical
}

private enum TextLayout {
    case horizontal(lines: [String], fontSize: CGFloat, lineHeight: CGFloat)
    case vertical(columns: [[String]], fontSize: CGFloat, lineHeight: CGFloat, columnWidth: CGFloat)

    var fontSize: CGFloat {
        switch self {
        case .horizontal(_, let fontSize, _),
             .vertical(_, let fontSize, _, _):
            return fontSize
        }
    }
}
