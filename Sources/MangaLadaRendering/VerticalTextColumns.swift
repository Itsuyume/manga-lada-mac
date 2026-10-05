import Foundation

/// Upright character order shared by titles and effects. No font or page state.
enum VerticalTextColumns {
    static func units(in text: String) -> [String] {
        text.filter { !$0.isWhitespace }.map { String($0) }
    }

    static func split(_ units: [String], maxRows: Int) -> [[String]] {
        guard maxRows > 0 else { return [] }
        return stride(from: 0, to: units.count, by: maxRows).map { start in
            Array(units[start..<min(start + maxRows, units.count)])
        }
    }
}
