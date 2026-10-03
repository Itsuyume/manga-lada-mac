import AppKit
import Foundation
import MangaLadaCore

extension TranslatedImageRenderer {
    func preferredTextFlow(for rect: NSRect, block: TextBlock, text: String) -> TextFlow {
        if block.textKind == .title, block.sourceIsVertical == true { return .vertical }
        return .horizontal
    }

    func fittedTextLayout(
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

    func fittedHorizontalTextLayout(
        for text: String,
        in rect: NSRect,
        scale: Double,
        detectedFontSize: Double?,
        backgroundStyle: TranslationTextBackgroundStyle
    ) -> TextLayout {
        let width = max(1, rect.width - 12)
        let height = max(1, rect.height - 8)
        let normalizedText = normalizedRenderableText(text)
        let characterCount = normalizedText.filter { !$0.isWhitespace }.count
        let requestedScale = max(0.7, min(CGFloat(scale), 2.4))
        let geometryLimit = min(rect.height * 0.34, rect.width * 0.24)
        let detectedLimit = detectedFontSize.map { CGFloat($0) * 0.98 }
        let sourceLimit: CGFloat
        if let detectedLimit, characterCount <= 8 {
            sourceLimit = min(detectedLimit, geometryLimit * 1.16)
        } else {
            sourceLimit = detectedLimit ?? geometryLimit
        }
        let maxSize = min(max(12, min(geometryLimit, sourceLimit)), 72) * requestedScale
        let minimumBase = max(backgroundStyle == .none ? 10 : 11, min(rect.width, rect.height) * 0.09)
        let minSize = max(8, min(max(minimumBase, 10), 28))

        var size = maxSize
        while size >= minSize {
            let font = preferredTextFont(ofSize: size, backgroundStyle: backgroundStyle)
            let lines = wrappedLines(for: normalizedText, maxWidth: width, font: font)
            let lineHeight = ceil(size * 1.08)
            let measuredHeight = CGFloat(lines.count) * lineHeight
            if !lines.isEmpty,
               measuredHeight <= height,
               lines.allSatisfy({ measuredWidth($0, font: font) <= width }) {
                return .horizontal(lines: lines, fontSize: size, lineHeight: lineHeight)
            }
            size -= 1
        }

        let hardMinSize = max(6, minSize * 0.62)
        var fallbackSize = minSize - 1
        while fallbackSize >= hardMinSize {
            let font = preferredTextFont(ofSize: fallbackSize, backgroundStyle: backgroundStyle)
            let lines = wrappedLines(for: normalizedText, maxWidth: width, font: font)
            let lineHeight = ceil(fallbackSize * 1.08)
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
            lineHeight: ceil(hardMinSize * 1.08)
        )
    }

    func fittedVerticalTextLayout(
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

    func preferredTextFont(ofSize size: CGFloat, backgroundStyle: TranslationTextBackgroundStyle) -> NSFont {
        let fontName = typography.dialogueFontName
        let fallbackWeight: NSFont.Weight = .bold
        return NSFont(name: fontName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: fallbackWeight)
    }

    func draw(
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
        case .shaped(let lines, _, _):
            for line in lines { attributedText(line.text, attributes: attributes).draw(in: line.rect) }
        case .horizontal(let lines, _, let lineHeight):
            drawHorizontal(lines: lines, lineHeight: lineHeight, attributes: attributes, in: bounds)
        case .vertical(let columns, _, let lineHeight, let columnWidth):
            drawVertical(columns: columns, lineHeight: lineHeight, columnWidth: columnWidth, attributes: attributes, in: bounds)
        }
    }

    func drawHorizontal(
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

    func drawVertical(
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

    func normalizedRenderableText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" ([,.!?…])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func wrappedLines(for text: String, maxWidth: CGFloat, font: NSFont) -> [String] {
        KoreanLineWrapper.wrap(text, widths: Array(repeating: maxWidth, count: max(1, text.count)),
                               measure: { measuredWidth($0, font: font) })
    }

    func verticalTextUnits(for text: String) -> [String] {
        normalizedRenderableText(text)
            .filter { !$0.isWhitespace }
            .map { String($0) }
    }

    func verticalColumns(for units: [String], maxRows: Int) -> [[String]] {
        guard maxRows > 0 else {
            return []
        }
        return stride(from: 0, to: units.count, by: maxRows).map { start in
            Array(units[start..<min(start + maxRows, units.count)])
        }
    }

    func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        attributedText(text, attributes: [.font: font]).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).width
    }

}

enum TextFlow {
    case horizontal
    case vertical
}

enum TextLayout {
    case shaped(lines: [PositionedTextLine], fontSize: CGFloat, lineHeight: CGFloat)
    case horizontal(lines: [String], fontSize: CGFloat, lineHeight: CGFloat)
    case vertical(columns: [[String]], fontSize: CGFloat, lineHeight: CGFloat, columnWidth: CGFloat)

    var fontSize: CGFloat {
        switch self {
        case .shaped(_, let fontSize, _): return fontSize
        case .horizontal(_, let fontSize, _),
             .vertical(_, let fontSize, _, _):
            return fontSize
        }
    }
}
