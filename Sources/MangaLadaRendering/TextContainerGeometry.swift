import AppKit
import Foundation
import MangaLadaCore

extension TranslatedImageRenderer {
    func occupiedTextRect(for layout: TextLayout, in bounds: NSRect) -> NSRect {
        switch layout {
        case .shaped(let lines, _, _): return lines.reduce(NSRect.null) { $0.union($1.rect) }
        case .horizontal(let lines, _, let lineHeight):
            let height = min(bounds.height, CGFloat(lines.count) * lineHeight)
            return NSRect(
                x: bounds.minX,
                y: bounds.midY - height / 2,
                width: bounds.width,
                height: max(1, height)
            )
        case .vertical(let columns, _, let lineHeight, let columnWidth):
            let width = min(bounds.width, CGFloat(columns.count) * columnWidth)
            let maxRows = columns.map(\.count).max() ?? 0
            let height = min(bounds.height, CGFloat(maxRows) * lineHeight)
            return NSRect(
                x: bounds.midX - width / 2,
                y: bounds.midY - height / 2,
                width: max(1, width),
                height: max(1, height)
            )
        }
    }

    func textBackingRect(
        for textRect: NSRect,
        in bubbleRect: NSRect,
        flow: TextFlow,
        backgroundStyle: TranslationTextBackgroundStyle
    ) -> NSRect {
        guard backgroundStyle == .readabilityBubble else {
            return bubbleRect
        }

        let insetX = flow == .vertical ? max(4, textRect.width * 0.08) : max(8, textRect.width * 0.08)
        let insetY = flow == .vertical ? max(6, textRect.height * 0.04) : max(8, textRect.height * 0.05)
        return clamp(textRect.insetBy(dx: -insetX, dy: -insetY), inside: bubbleRect)
    }

    func textDrawingRect(
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
            max(84, bubbleRect.width * 0.84)
        )
        let preferredX = originalTextRect.midX - columnWidth / 2
        let minX = bestLightColumnX(
            in: baseRect,
            columnWidth: columnWidth,
            lightRegionDetector: lightRegionDetector
        ) ?? max(baseRect.minX, min(baseRect.maxX - columnWidth, preferredX))
        return NSRect(
            x: minX,
            y: baseRect.minY,
            width: columnWidth,
            height: baseRect.height
        )
    }

    func bestLightColumnX(
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

    func textContainerRect(
        fallbackRect: NSRect,
        originalTextRect: NSRect,
        imageSize: NSSize,
        flow: TextFlow,
        backgroundStyle: TranslationTextBackgroundStyle,
        lightRegionDetector: LightRegionDetector?
    ) -> NSRect {
        guard backgroundStyle == .none else { return fallbackRect }
        // Floating text uses a bounded horizontal strip and an outline over artwork.
        // Its vertical extent stays inside the original ink bounds.
        guard flow == .horizontal, originalTextRect.height >= originalTextRect.width * 1.4 else { return originalTextRect }
        let widthLimit = max(originalTextRect.width, min(max(originalTextRect.height * 0.7, originalTextRect.width * 2.5), imageSize.width * 0.16))
        let span = lightRegionDetector?.horizontalLightSpan(around: originalTextRect, maximumWidth: widthLimit)
            ?? NSRect(x: originalTextRect.midX - widthLimit / 2, y: originalTextRect.minY, width: widthLimit, height: originalTextRect.height)
        let constrained = lightRegionDetector?.constrainedToPanel(span, around: originalTextRect) ?? span
        return clamped(constrained, imageSize: imageSize)
    }

    func pixelBackedSize(for image: NSImage) -> NSSize {
        if let representation = image.representations.first {
            let width = representation.pixelsWide > 0 ? representation.pixelsWide : Int(image.size.width)
            let height = representation.pixelsHigh > 0 ? representation.pixelsHigh : Int(image.size.height)
            return NSSize(width: width, height: height)
        }
        return image.size
    }

    func pixelRect(for box: TextBox, imageSize: NSSize) -> NSRect {
        let x = box.x * imageSize.width
        let yFromTop = box.y * imageSize.height
        let width = max(1, box.width * imageSize.width)
        let height = max(1, box.height * imageSize.height)
        return NSRect(x: x, y: imageSize.height - yFromTop - height, width: width, height: height)
    }

    func redactionRect(
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

    func clamped(_ rect: NSRect, imageSize: NSSize) -> NSRect {
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

    func clamp(_ rect: NSRect, inside bounds: NSRect) -> NSRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = max(bounds.minX, min(bounds.maxX - width, rect.minX))
        let y = max(bounds.minY, min(bounds.maxY - height, rect.minY))
        return NSRect(x: x, y: y, width: max(1, width), height: max(1, height))
    }

}
