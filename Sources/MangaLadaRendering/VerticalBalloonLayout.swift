import AppKit
import MangaLadaCore

extension TranslatedImageRenderer {
    /// Manual upright text still has to fit every sampled row of its balloon.
    func fittedVerticalBalloonLayout(text: String, shape: BalloonShape, imageSize: NSSize,
                                     fontSize: Double, scale: Double, fixedSize: Bool) throws -> TextLayout? {
        let bounds = pixelRect(for: shape.bounds, imageSize: imageSize)
        let preferred = fixedSize ? max(4, fontSize * scale) : min(96, max(16, fontSize * scale))
        let minimum = max(8, min(preferred * 0.6, DialogueTypesettingRules.referenceWidth(imageSize) * 0.0105))
        let sizes = fixedSize ? [preferred]
            : Array(Set(DialogueTypesettingRules.sizeSteps.map { max(minimum, preferred * $0) } + [minimum])).sorted(by: >)
        for wrap in [false, true] {
            for size in sizes {
                let font = preferredTextFont(ofSize: size, backgroundStyle: .none)
                let layout = try LetteringTextLayout.vertical(text, height: bounds.height - 8, allowWrap: wrap) {
                    attributedText($0, attributes: [.font: font])
                }
                if let lines = verticalBalloonLines(layout, shape: shape, imageSize: imageSize, margin: max(2, size * 0.1)) {
                    return .shaped(lines: lines, fontSize: size, lineHeight: font.ascender - font.descender + font.leading)
                }
            }
        }
        return nil
    }

    private func verticalBalloonLines(_ layout: LetteringTextLayout, shape: BalloonShape,
                                      imageSize: NSSize, margin: CGFloat) -> [PositionedTextLine]? {
        let bounds = pixelRect(for: shape.bounds, imageSize: imageSize)
        guard !layout.runs.isEmpty, layout.size.width + margin * 2 <= bounds.width,
              layout.size.height + margin * 2 <= bounds.height else { return nil }
        for center in DialogueTypesettingRules.centerFractions {
            let lines = layout.runs.map {
                PositionedTextLine(text: $0.text.string, rect: $0.rect.offsetBy(dx: bounds.midX, dy: bounds.minY + bounds.height * center))
            }
            if lines.allSatisfy({ containsLetteringRect($0.rect.insetBy(dx: -margin, dy: -margin), shape: shape, imageSize: imageSize) }) {
                return lines
            }
        }
        return nil
    }

    private func containsLetteringRect(_ rect: NSRect, shape: BalloonShape, imageSize: NSSize) -> Bool {
        guard pixelRect(for: shape.bounds, imageSize: imageSize).contains(rect) else { return false }
        let top = 1 - rect.maxY / imageSize.height, bottom = 1 - rect.minY / imageSize.height
        let rows = shape.rows.filter { $0.y >= top && $0.y <= bottom }
        return !rows.isEmpty && rows.allSatisfy { $0.left * imageSize.width <= rect.minX && $0.right * imageSize.width >= rect.maxX }
    }
}
