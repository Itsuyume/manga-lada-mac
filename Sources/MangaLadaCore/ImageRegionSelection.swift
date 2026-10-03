import Foundation

/// Coordinates are relative to the displayed image, never the scroll view or window.
public enum ImageRegionSelection {
    public static func box(from start: CGPoint, to end: CGPoint, in size: CGSize) -> TextBox? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
              start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { return nil }
        let left = max(0, min(start.x, end.x)), top = max(0, min(start.y, end.y))
        let right = min(size.width, max(start.x, end.x)), bottom = min(size.height, max(start.y, end.y))
        guard right - left >= 3, bottom - top >= 3 else { return nil }
        return TextBox(x: left / size.width, y: top / size.height, width: (right - left) / size.width, height: (bottom - top) / size.height)
    }
    public static func validates(_ box: TextBox) -> Bool {
        [box.x, box.y, box.width, box.height].allSatisfy(\.isFinite) && box.x >= 0 && box.y >= 0 && box.width > 0 && box.height > 0
            && box.x + box.width <= 1.000001 && box.y + box.height <= 1.000001
    }
    public static func containsCenter(_ box: TextBox, of other: TextBox) -> Bool {
        let x = other.x + other.width / 2, y = other.y + other.height / 2
        return x >= box.x && x <= box.x + box.width && y >= box.y && y <= box.y + box.height
    }
    /// Multiple enclosed bubbles keep separate rectangular cells and separate translations.
    public static func partitions(_ selection: TextBox, blocks: [TextBlock]) throws -> [UUID: TextBox] {
        try validatePartition(selection, blocks: blocks)
        var cells: [UUID: TextBox] = [:]
        for block in blocks {
            let x = block.box.x + block.box.width / 2, y = block.box.y + block.box.height / 2
            var left = selection.x, top = selection.y, right = left + selection.width, bottom = top + selection.height
            for other in blocks where other.id != block.id {
                let ox = other.box.x + other.box.width / 2, oy = other.box.y + other.box.height / 2
                if abs(x - ox) / selection.width >= abs(y - oy) / selection.height {
                    if x < ox { right = min(right, (x + ox) / 2) } else { left = max(left, (x + ox) / 2) }
                } else {
                    if y < oy { bottom = min(bottom, (y + oy) / 2) } else { top = max(top, (y + oy) / 2) }
                }
            }
            cells[block.id] = TextBox(x: left, y: top, width: right - left, height: bottom - top)
        }
        return cells
    }
    private static func validatePartition(_ selection: TextBox, blocks: [TextBlock]) throws {
        guard validates(selection) else { throw RegionPartitionError.invalidBounds }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw RegionPartitionError.duplicateRegions }
        for (index, block) in blocks.enumerated() {
            guard validates(block.box), containsCenter(selection, of: block.box) else { throw RegionPartitionError.invalidBounds }
            let x = block.box.x + block.box.width / 2, y = block.box.y + block.box.height / 2
            for other in blocks.dropFirst(index + 1) {
                let ox = other.box.x + other.box.width / 2, oy = other.box.y + other.box.height / 2
                guard abs(x - ox) > 0.000001 || abs(y - oy) > 0.000001 else { throw RegionPartitionError.duplicateRegions }
            }
        }
    }
}

public enum RegionPartitionError: LocalizedError {
    case invalidBounds, duplicateRegions
    public var errorDescription: String? {
        switch self {
        case .invalidBounds: "말풍선 중심이 선택 영역 안에 들어오도록 다시 드래그해주세요."
        case .duplicateRegions: "같은 위치에 문구 영역이 겹쳐 있습니다. 말풍선을 하나씩 지정해주세요."
        }
    }
}
