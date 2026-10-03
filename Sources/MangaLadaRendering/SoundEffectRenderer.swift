import AppKit
import MangaLadaCore

@MainActor
enum SoundEffectRenderer {
    private struct Layout {
        let text: NSAttributedString
        let bounds: NSRect
        let angle: CGFloat
        let shear: CGFloat
        let widthScale: CGFloat
    }
    static func draw(_ block: TextBlock, in rect: NSRect, typography: MangaTypography, scale: Double) throws {
        let text = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let style = try selectedStyle(block, typography: typography)
        let layout = try fit(text, block: block, rect: rect, style: style, typography: typography, scale: scale)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byRadians: -layout.angle)
        let deformation = NSAffineTransform()
        deformation.transformStruct = NSAffineTransformStruct(m11: layout.widthScale, m12: 0, m21: layout.shear, m22: 1, tX: 0, tY: 0)
        transform.concat(); deformation.concat()
        let drawingRect = NSRect(x: -layout.bounds.width / 2, y: -layout.bounds.height / 2,
                                 width: layout.bounds.width, height: layout.bounds.height)
        layout.text.draw(in: drawingRect)
        // A centered outline covers fine glyph strokes. Repaint the original fill over it.
        let fill = NSMutableAttributedString(attributedString: layout.text)
        let range = NSRange(location: 0, length: fill.length)
        fill.removeAttribute(.strokeWidth, range: range)
        fill.removeAttribute(.strokeColor, range: range)
        fill.draw(in: drawingRect)
    }
    private static func selectedStyle(_ block: TextBlock, typography: MangaTypography) throws -> SoundEffectStyle? {
        guard let id = block.effectStyleID ?? typography.effectStyleID, id != "custom" else { return nil }
        try SoundEffectFonts.registerBundledFonts()
        let library = try SoundEffectLibrary.standard()
        return try id == "automatic" ? library.automaticStyle(original: block.originalText, translated: block.translatedText) : library.style(id: id)
    }
    private static func fit(_ text: String, block: TextBlock, rect: NSRect, style: SoundEffectStyle?,
                            typography: MangaTypography, scale: Double) throws -> Layout {
        let angle = CGFloat(block.rotationDegrees ?? 0) * .pi / 180
        let shear = CGFloat(style?.shear ?? 0), widthScale = CGFloat(style?.widthScale ?? 1)
        let denominator = max(1, abs(cos(angle)) + abs(sin(angle)))
        let width = max(1, (rect.width - 8) / denominator / (widthScale + abs(shear)))
        let height = max(1, (rect.height - 8) / denominator)
        let maximum = min(160, max(12, CGFloat(block.detectedFontSize ?? Double(min(width, height))) * CGFloat(scale)))
        guard Double(text.count) * 36 < Double(rect.width * rect.height) * 2 else {
            throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
        }
        for size in stride(from: maximum, through: 10, by: -1) {
            let attributed = try attributedText(text, size: size, style: style, typography: typography)
            let bounds = attributed.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading]).integral
            let x = bounds.width * widthScale + bounds.height * abs(shear), y = bounds.height
            let rotatedWidth = abs(cos(angle)) * x + abs(sin(angle)) * y
            let rotatedHeight = abs(sin(angle)) * x + abs(cos(angle)) * y
            if bounds.height <= height, rotatedWidth + 8 <= rect.width, rotatedHeight + 8 <= rect.height {
                return Layout(text: attributed, bounds: bounds, angle: angle, shear: shear, widthScale: widthScale)
            }
        }
        throw TranslatedImageRenderError.textDoesNotFit(block.id, text)
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
