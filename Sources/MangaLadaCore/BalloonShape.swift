import Foundation

/// Balloon interior, sampled in normalized source-image coordinates.
public struct BalloonShape: Codable, Equatable, Sendable {
    public let bounds: TextBox
    public let rows: [BalloonShapeRow]
    public init(bounds: TextBox, rows: [BalloonShapeRow]) { self.bounds = bounds; self.rows = rows }
    public func clipped(to box: TextBox) -> BalloonShape? {
        let left = max(bounds.x, box.x), top = max(bounds.y, box.y)
        let right = min(bounds.x + bounds.width, box.x + box.width), bottom = min(bounds.y + bounds.height, box.y + box.height)
        guard right > left, bottom > top else { return nil }
        let clipped = rows.filter { $0.y >= top && $0.y <= bottom }.compactMap { row -> BalloonShapeRow? in
            let start = max(left, row.left), end = min(right, row.right)
            return end > start ? BalloonShapeRow(y: row.y, left: start, right: end) : nil
        }
        guard clipped.count >= 3 else { return nil }
        return BalloonShape(bounds: TextBox(x: left, y: top, width: right - left, height: bottom - top), rows: clipped)
    }
}

public struct BalloonShapeRow: Codable, Equatable, Sendable {
    public let y: Double
    public let left: Double
    public let right: Double
    public init(y: Double, left: Double, right: Double) { self.y = y; self.left = left; self.right = right }
}
