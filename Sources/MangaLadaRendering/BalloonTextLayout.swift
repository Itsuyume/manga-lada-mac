import AppKit
import MangaLadaCore

struct PositionedTextLine {
    let text: String
    let rect: NSRect
}

extension TranslatedImageRenderer {
    func drawBalloon(block: TextBlock, text: String, imageSize: NSSize, pageFontSize: Double, fontScale: Double,
                     lightRegionDetector: LightRegionDetector?) throws {
        let inkRect = pixelRect(for: block.box, imageSize: imageSize)
        let container = textContainerRect(fallbackRect: inkRect, originalTextRect: inkRect, imageSize: imageSize,
                                          flow: .horizontal, backgroundStyle: .none, lightRegionDetector: lightRegionDetector)
        let containerBox = TextBox(x: container.minX / imageSize.width, y: 1 - container.maxY / imageSize.height,
                                   width: container.width / imageSize.width, height: container.height / imageSize.height)
        let shape: BalloonShape
        if let selected = block.userDefinedBounds {
            if let contour = block.balloonShape {
                guard let clipped = contour.clipped(to: selected) else { throw TranslatedImageRenderError.textDoesNotFit(block.id, text) }
                shape = clipped
            } else { shape = DialogueTypesettingRules.rectangularShape(box: selected) }
        } else { shape = block.balloonShape ?? DialogueTypesettingRules.rectangularShape(box: containerBox) }
        guard let layout = fittedBalloonLayout(text: text, shape: shape, imageSize: imageSize, fontSize: pageFontSize,
                                               scale: fontScale, hasContour: block.balloonShape != nil || block.userDefinedBounds != nil) else {
            throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
        }
        var attributes = textAttributes(size: layout.fontSize, backgroundStyle: .none)
        let dark = (lightRegionDetector?.medianLuminance(in: pixelRect(for: shape.bounds, imageSize: imageSize)) ?? 1) < 0.5
        attributes[.foregroundColor] = dark ? NSColor.white : NSColor.black
        attributes[.strokeColor] = dark ? NSColor.black : NSColor.white
        attributes[.strokeWidth] = block.balloonShape == nil && block.userDefinedBounds == nil ? -4.0 : -1.0
        draw(layout: layout, attributes: attributes, in: pixelRect(for: shape.bounds, imageSize: imageSize))
    }

    func fittedBalloonLayout(text: String, shape: BalloonShape, imageSize: NSSize, fontSize: Double,
                            scale: Double, hasContour: Bool) -> TextLayout? {
        let bounds = pixelRect(for: shape.bounds, imageSize: imageSize)
        let preferred = min(96, max(16, fontSize * scale))
        let minimum = max(10, min(DialogueTypesettingRules.referenceWidth(imageSize) * 0.0105, bounds.width * 0.22))
        let minimumFont = preferredTextFont(ofSize: minimum, backgroundStyle: .none)
        let capacity = bounds.width * CGFloat(min(50, Int(floor(bounds.height / ceil(minimum * DialogueTypesettingRules.lineSpacing)))))
        guard measuredWidth(text.filter { !$0.isWhitespace }, font: minimumFont) <= capacity else { return nil }
        let candidates = Array(Set(DialogueTypesettingRules.sizeSteps.map { max(minimum, preferred * $0) } + [minimum])).sorted(by: >)
        for size in candidates {
            let allowWordBreaks = size <= preferred * 0.8
            if let layout = layoutAtSize(text: text, shape: shape, imageSize: imageSize, bounds: bounds, size: size,
                                          hasContour: hasContour, allowWordBreaks: allowWordBreaks) { return layout }
        }
        return nil
    }
    private func layoutAtSize(text: String, shape: BalloonShape, imageSize: NSSize, bounds: NSRect,
                              size: CGFloat, hasContour: Bool, allowWordBreaks: Bool) -> TextLayout? {
        let font = preferredTextFont(ofSize: size, backgroundStyle: .none)
        let lineHeight = ceil(size * DialogueTypesettingRules.lineSpacing)
        let maximumRows = min(50, Int(floor((bounds.height - (hasContour ? size * 0.7 : 0)) / lineHeight)))
        guard maximumRows > 0 else { return nil }
        let centers = hasContour ? DialogueTypesettingRules.centerFractions : [0.5]
        for count in 1...maximumRows {
            for fraction in centers {
                let rectangles = balloonLineRects(shape: shape, imageSize: imageSize, bounds: bounds,
                                                   count: count, height: lineHeight, centerY: bounds.minY + bounds.height * fraction,
                                                   margin: hasContour ? max(4, size * DialogueTypesettingRules.insetRatio) : 2)
                guard rectangles.count == count else { continue }
                let lines = KoreanLineWrapper.balanced(normalizedRenderableText(text), widths: rectangles.map(\.width), allowWordBreaks: allowWordBreaks,
                                                    measure: { measuredWidth($0, font: font) })
                guard lines.count == count else { continue }
                return .shaped(lines: zip(lines, rectangles).map { PositionedTextLine(text: $0.0, rect: $0.1) }, fontSize: size, lineHeight: lineHeight)
            }
        }
        return nil
    }
    private func balloonLineRects(shape: BalloonShape, imageSize: NSSize, bounds: NSRect,
                                  count: Int, height: CGFloat, centerY: CGFloat, margin: CGFloat) -> [NSRect] {
        let top = centerY + CGFloat(count) * height / 2
        guard top <= bounds.maxY, top - CGFloat(count) * height >= bounds.minY else { return [] }
        return (0..<count).compactMap { index in
            let bottom = top - CGFloat(index + 1) * height
            let samples = shape.rows.filter { row in
                let y = imageSize.height * (1 - row.y)
                return y >= bottom - 2 && y <= bottom + height + 2
            }
            guard let left = samples.map(\.left).max(), let right = samples.map(\.right).min() else { return nil }
            let available = (right - left) * imageSize.width
            let inset = min(margin, max(2, available * DialogueTypesettingRules.maximumInsetFraction))
            let x = left * imageSize.width + inset
            let width = available - inset * 2
            guard width > 8 else { return nil }
            return NSRect(x: x, y: bottom, width: width, height: height)
        }
    }
}
