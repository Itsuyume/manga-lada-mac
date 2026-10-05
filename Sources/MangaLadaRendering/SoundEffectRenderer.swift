import AppKit
import MangaLadaCore

@MainActor
enum SoundEffectRenderer {
    private struct Layout {
        let lettering: LetteringTextLayout
        let angle: CGFloat
        let shear: CGFloat
        let widthScale: CGFloat
        let fontSize: CGFloat
    }
    static func draw(_ block: TextBlock, in rect: NSRect, typography: MangaTypography, scale: Double, source: SourceLettering? = nil) throws {
        let text = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let style = try LetteringStylePolicy.selected(block, typography: typography, source: source)
        let automatic = try fit(text, block: block, rect: rect, style: style, typography: typography, scale: scale)
        let layout = try block.fontScale.map {
            try fit(text, block: block, rect: rect, style: style, typography: typography, scale: scale,
                    fixedSize: automatic.fontSize * $0)
        } ?? automatic
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byRadians: -layout.angle)
        let deformation = NSAffineTransform()
        deformation.transformStruct = NSAffineTransformStruct(m11: layout.widthScale, m12: 0, m21: layout.shear, m22: 1, tX: 0, tY: 0)
        transform.concat(); deformation.concat()
        for run in layout.lettering.runs { draw(run) }
    }
    private static func draw(_ run: LetteringTextLayout.Run) {
        run.text.draw(in: run.rect)
        // A centered outline covers fine glyph strokes. Repaint the original fill over it.
        let fill = NSMutableAttributedString(attributedString: run.text)
        let range = NSRange(location: 0, length: fill.length)
        fill.removeAttribute(.strokeWidth, range: range)
        fill.removeAttribute(.strokeColor, range: range)
        fill.draw(in: run.rect)
    }
    private static func fit(_ text: String, block: TextBlock, rect: NSRect, style: SoundEffectStyle?,
                            typography: MangaTypography, scale: Double, fixedSize: CGFloat? = nil) throws -> Layout {
        let angle = CGFloat(block.rotationDegrees ?? 0) * .pi / 180
        let shear = CGFloat(style?.shear ?? 0), widthScale = CGFloat(style?.widthScale ?? 1)
        let denominator = max(1, abs(cos(angle)) + abs(sin(angle)))
        let width = max(1, (rect.width - 8) / denominator / (widthScale + abs(shear)))
        let height = max(1, (rect.height - 8) / denominator)
        let maximum = min(160, max(12, CGFloat(block.detectedFontSize ?? Double(min(width, height))) * CGFloat(scale)))
        guard Double(text.count) * 36 < Double(rect.width * rect.height) * 2 else {
            throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
        }
        let vertical = block.textDirection.map { $0 == .vertical }
            ?? block.sourceIsVertical ?? (rect.height >= rect.width * 1.45)
        for allowWrap in vertical ? [false, true] : [false] {
            let sizes = fixedSize.map { [$0] } ?? Array(stride(from: maximum, through: 10, by: -1))
            for size in sizes {
                let lettering = try textLayout(text, vertical: vertical, allowWrap: allowWrap, size: size,
                                               width: width, height: height, style: style, typography: typography)
                let x = lettering.size.width * widthScale + lettering.size.height * abs(shear), y = lettering.size.height
                let rotatedWidth = abs(cos(angle)) * x + abs(sin(angle)) * y
                let rotatedHeight = abs(sin(angle)) * x + abs(cos(angle)) * y
                if lettering.size.height <= height, rotatedWidth + 8 <= rect.width, rotatedHeight + 8 <= rect.height {
                    return Layout(lettering: lettering, angle: angle, shear: shear, widthScale: widthScale, fontSize: size)
                }
            }
        }
        throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
    }
    private static func textLayout(_ text: String, vertical: Bool, allowWrap: Bool, size: CGFloat,
                                   width: CGFloat, height: CGFloat, style: SoundEffectStyle?, typography: MangaTypography) throws -> LetteringTextLayout {
        if vertical {
            return try .vertical(text, height: height, allowWrap: allowWrap) { unit in
                try attributedText(unit, size: size, style: style, typography: typography)
            }
        }
        let attributed = try attributedText(text, size: size, style: style, typography: typography)
        let measureWidth: CGFloat = text.count <= 6 && !text.contains("\n") ? .greatestFiniteMagnitude : width
        return .horizontal(attributed, width: measureWidth)
    }
    private static func attributedText(_ text: String, size: CGFloat, style: SoundEffectStyle?,
                                       typography: MangaTypography) throws -> NSAttributedString {
        let name = style?.fontName ?? typography.effectFontName
        guard let font = NSFont(name: name, size: size) else { throw SoundEffectLibraryError.fontUnavailable(name) }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byCharWrapping
        let outline = style?.outline ?? 5
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font, .paragraphStyle: paragraph, .kern: size * CGFloat(style?.tracking ?? 0),
            .foregroundColor: NSColor.black, .strokeColor: NSColor.white, .strokeWidth: -outline
        ]
        if style?.hollow == true {
            attributes[.foregroundColor] = NSColor.white; attributes[.strokeColor] = NSColor.black
        }
        return NSAttributedString(string: text, attributes: attributes)
    }
}
