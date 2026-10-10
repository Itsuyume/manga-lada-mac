import AppKit
import MangaLadaCore

struct PositionedTextLine {
    let text: String
    let rect: NSRect
}

extension TranslatedImageRenderer {
    func drawBalloon(block: TextBlock, text: String, imageSize: NSSize, pageFontSize: Double, fontScale: Double,
                     shape: BalloonShape, sourceLettering: SourceLettering?, lightRegionDetector: LightRegionDetector?) throws {
        var styled = block
        let expressive = LetteringStylePolicy.expressiveDialogue(block, pageFontSize: pageFontSize)
        if expressive, styled.effectStyleID == nil { styled.effectStyleID = "brush" }
        var selectedTypography = typography
        if let style = try LetteringStylePolicy.selected(styled, typography: typography, source: sourceLettering) {
            selectedTypography.dialogueFontName = style.fontName
        }
        let renderer = TranslatedImageRenderer(typography: selectedTypography)
        let balloonSize = DialogueTypesettingRules.balloonFontSize(text: text, shape: shape, imageSize: imageSize, pageFontSize: pageFontSize)
        let desiredSize = expressive ? max(balloonSize, (block.detectedFontSize ?? pageFontSize) * 0.75) : balloonSize
        let layout = try renderer.balloonLayout(block: block, text: text, shape: shape, imageSize: imageSize,
                                                desiredSize: desiredSize, scale: fontScale)
        var attributes = renderer.textAttributes(size: layout.fontSize, backgroundStyle: .none)
        let dark = (lightRegionDetector?.medianLuminance(in: pixelRect(for: shape.bounds, imageSize: imageSize)) ?? 1) < 0.5
        attributes[.foregroundColor] = dark ? NSColor.white : NSColor.black
        attributes[.strokeColor] = dark ? NSColor.black : NSColor.white
        attributes[.strokeWidth] = block.balloonShape == nil && block.userDefinedBounds == nil ? -4.0 : -1.0
        draw(layout: layout, attributes: attributes, in: pixelRect(for: shape.bounds, imageSize: imageSize))
    }

    private func balloonLayout(block: TextBlock, text: String, shape: BalloonShape, imageSize: NSSize,
                               desiredSize: Double, scale: Double) throws -> TextLayout {
        let hasContour = block.balloonShape != nil || block.textLayoutBounds != nil || block.userDefinedBounds != nil
        func fit(_ size: Double, fixed: Bool) throws -> TextLayout? {
            if block.textDirection == .vertical {
                return try fittedVerticalBalloonLayout(text: text, shape: shape, imageSize: imageSize,
                                                        fontSize: size, scale: 1, fixedSize: fixed)
            }
            return fittedBalloonLayout(text: text, shape: shape, imageSize: imageSize,
                                       fontSize: size, scale: 1, hasContour: hasContour, fixedSize: fixed)
        }
        guard let automatic = try fit(desiredSize * scale, fixed: false) else {
            throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
        }
        guard let multiplier = block.fontScale else { return automatic }
        guard let manual = try fit(automatic.fontSize * multiplier, fixed: true) else {
            throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
        }
        return manual
    }

    func fittedBalloonLayout(text: String, shape: BalloonShape, imageSize: NSSize, fontSize: Double,
                            scale: Double, hasContour: Bool, fixedSize: Bool = false) -> TextLayout? {
        let bounds = pixelRect(for: shape.bounds, imageSize: imageSize)
        let preferred = fixedSize ? max(4, fontSize * scale) : min(96, max(16, fontSize * scale))
        let minimum = max(8, min(preferred * 0.6, DialogueTypesettingRules.referenceWidth(imageSize) * 0.0105))
        let minimumFont = preferredTextFont(ofSize: minimum, backgroundStyle: .none)
        let capacity = bounds.width * CGFloat(min(50, Int(floor(bounds.height / ceil(minimum * DialogueTypesettingRules.lineSpacing)))))
        guard measuredWidth(text.filter { !$0.isWhitespace }, font: minimumFont) <= capacity else { return nil }
        let candidates = fixedSize ? [preferred]
            : Array(Set(DialogueTypesettingRules.sizeSteps.map { max(minimum, preferred * $0) } + [minimum])).sorted(by: >)
        // Fit whole Korean words at every readable size before breaking a word.
        for allowWordBreaks in [false, true] {
            for size in candidates {
                if let layout = layoutAtSize(text: text, shape: shape, imageSize: imageSize, bounds: bounds, size: size,
                                              hasContour: hasContour, allowWordBreaks: allowWordBreaks) { return layout }
            }
        }
        return nil
    }
    private func layoutAtSize(text: String, shape: BalloonShape, imageSize: NSSize, bounds: NSRect,
                              size: CGFloat, hasContour: Bool, allowWordBreaks: Bool) -> TextLayout? {
        let font = preferredTextFont(ofSize: size, backgroundStyle: .none)
        let lineHeight = ceil(max(size * DialogueTypesettingRules.lineSpacing, font.ascender - font.descender + font.leading))
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
