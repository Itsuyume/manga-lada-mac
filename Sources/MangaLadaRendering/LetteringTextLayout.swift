import AppKit

@MainActor
struct LetteringTextLayout {
    struct Run {
        let text: NSAttributedString
        let rect: NSRect
    }
    let runs: [Run]
    let size: NSSize

    static func horizontal(_ text: NSAttributedString, width: CGFloat) -> Self {
        let bounds = measure(text, width: width)
        return Self(runs: [Run(text: text, rect: NSRect(x: -bounds.width / 2, y: -bounds.height / 2,
                                                       width: bounds.width, height: bounds.height))], size: bounds.size)
    }

    /// Explicit newlines start another column; short phrases keep a whole column before shrinking.
    static func vertical(_ text: String, height: CGFloat, allowWrap: Bool,
                         attributed: (String) throws -> NSAttributedString) throws -> Self {
        let units = VerticalTextColumns.units(in: text)
        guard !units.isEmpty else { return Self(runs: [], size: .zero) }
        let glyphs = try Dictionary(uniqueKeysWithValues: Set(units).map { ($0, try attributed($0)) })
        let dimensions = glyphs.values.map { measure($0) }
        let rowHeight = ceil(dimensions.map(\.height).max() ?? 0)
        let columnWidth = ceil((dimensions.map(\.width).max() ?? 0) * 1.12)
        let maxRows = allowWrap ? max(1, Int(floor(height / max(1, rowHeight)))) : units.count
        let columns = text.components(separatedBy: .newlines).flatMap {
            VerticalTextColumns.split(VerticalTextColumns.units(in: $0), maxRows: maxRows)
        }
        let size = NSSize(width: CGFloat(columns.count) * columnWidth,
                          height: CGFloat(columns.map(\.count).max() ?? 0) * rowHeight)
        let runs = try columns.enumerated().flatMap { index, column in
            try column.enumerated().map { row, unit -> Run in
                let glyph = try attributed(unit)
                let rect = NSRect(x: size.width / 2 - CGFloat(index + 1) * columnWidth,
                                  y: CGFloat(column.count) * rowHeight / 2 - CGFloat(row + 1) * rowHeight,
                                  width: columnWidth, height: rowHeight)
                return Run(text: glyph, rect: rect)
            }
        }
        return Self(runs: runs, size: size)
    }

    private static func measure(_ text: NSAttributedString, width: CGFloat = .greatestFiniteMagnitude) -> NSRect {
        text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading]).integral
    }
}
