import Foundation
import MangaLadaCore

/// Vision reports cropped-input coordinates. Normalize them once at the OCR boundary.
package enum VisionRegionRecognition {
    package static func project(_ box: TextBox, into region: TextBox) -> TextBox? {
        guard [box.x, box.y, box.width, box.height].allSatisfy(\.isFinite) else { return nil }
        let left = max(0, box.x), top = max(0, box.y)
        let right = min(1, box.x + box.width), bottom = min(1, box.y + box.height)
        guard left < right, top < bottom else { return nil }
        return TextBox(x: region.x + left * region.width, y: region.y + top * region.height,
                       width: (right-left) * region.width, height: (bottom-top) * region.height)
    }

    package static func combine(global: [TextBlock], regional: [(TextBox, [TextBlock])]) -> [TextBlock] {
        // Empty regional readings cannot suppress a full-page observation.
        let covered = regional.filter { !$0.1.isEmpty }
        let retained = global.filter { block in
            let overlap = covered.reduce(0.0) { amount, reading in
                amount + (block.box.height < reading.0.height * 0.85 ? block.box.intersectionArea(with: reading.0) : 0)
            }
            return overlap < block.box.area * 0.4
        }
        let candidates = (covered.flatMap(\.1) + retained).sorted { $0.box.area > $1.box.area }
        var result: [TextBlock] = []
        for block in candidates {
            let duplicate = result.contains { old in
                old.box.intersectionArea(with: block.box) >= block.box.area * 0.7
                    && (old.originalText == block.originalText || old.box.area > block.box.area * 2.5)
            }
            if !duplicate { result.append(block) }
        }
        return result
    }
}
