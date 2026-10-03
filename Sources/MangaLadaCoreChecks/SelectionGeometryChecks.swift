import Foundation
import MangaLadaCore

enum SelectionGeometryChecks {
    static func run() throws {
        let size = CGSize(width: 800, height: 600)
        let expected = TextBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        try require(ImageRegionSelection.box(from: CGPoint(x: 80, y: 120), to: CGPoint(x: 320, y: 360), in: size) == expected, "Selection has wrong coordinates.")
        try require(ImageRegionSelection.box(from: CGPoint(x: 320, y: 360), to: CGPoint(x: 80, y: 120), in: size) == expected, "Reverse drag changed the selected region.")
        try require(ImageRegionSelection.box(from: CGPoint(x: -40, y: -20), to: CGPoint(x: 900, y: 700), in: size) == TextBox(x: 0, y: 0, width: 1, height: 1), "Out-of-image drag was not clamped.")
        try require(ImageRegionSelection.box(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 2, y: 1), in: size) == nil, "Click/tiny drag made an OCR request.")
        try require(ImageRegionSelection.box(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 4, y: 4), in: CGSize(width: 0, height: 0)) == nil, "Empty viewport made invalid coordinates.")
        try require(!ImageRegionSelection.validates(TextBox(x: 0, y: 0, width: .nan, height: 0.1)), "NaN selection was accepted.")
        try require(!ImageRegionSelection.validates(TextBox(x: 0.9, y: 0, width: 0.2, height: 0.1)), "Overflow selection was accepted.")
        let encoded = try JSONEncoder().encode(TextBlock(box: expected, originalText: "あっ", userDefinedBounds: expected))
        try require(try JSONDecoder().decode(TextBlock.self, from: encoded).userDefinedBounds == expected, "Manual bounds did not persist.")
        try partitionChecks()
        print("Selection checks passed: reverse drag, normalized coordinates, clipping, empty/tiny/invalid input, persisted bounds, separate stable numbered regions")
    }
    private static func partitionChecks() throws {
        let selection = TextBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        try require(try ImageRegionSelection.partitions(selection, blocks: []).isEmpty, "Empty selection invented regions.")
        let blocks = [TextBlock(box: TextBox(x: 0.2, y: 0.2, width: 0.1, height: 0.1), originalText: "一"),
                      TextBlock(box: TextBox(x: 0.6, y: 0.5, width: 0.1, height: 0.1), originalText: "二"),
                      TextBlock(box: TextBox(x: 0.2, y: 0.7, width: 0.1, height: 0.1), originalText: "三")]
        let cells = try ImageRegionSelection.partitions(selection, blocks: blocks)
        try require(cells.count == blocks.count, "Multiple bubbles merged or lost identities.")
        try require(cells == ImageRegionSelection.partitions(selection, blocks: blocks.reversed()), "Partition changed with input order.")
        for block in blocks {
            guard let cell = cells[block.id] else { throw SelectionCheckFailure.failed("Numbered bubble missing.") }
            try require(ImageRegionSelection.validates(cell) && ImageRegionSelection.containsCenter(cell, of: block.box), "Bubble cell excluded its own text.")
            for other in cells.values where other != cell {
                let overlapWidth = min(cell.x + cell.width, other.x + other.width) - max(cell.x, other.x)
                let overlapHeight = min(cell.y + cell.height, other.y + other.height) - max(cell.y, other.y)
                try require(overlapWidth <= 0.000001 || overlapHeight <= 0.000001, "Separate bubble cells overlap.")
            }
        }
        do {
            _ = try ImageRegionSelection.partitions(selection, blocks: [blocks[0], blocks[0]])
            throw SelectionCheckFailure.failed("Duplicate identities were accepted.")
        } catch RegionPartitionError.duplicateRegions { }
        do {
            _ = try ImageRegionSelection.partitions(selection, blocks: [blocks[0], TextBlock(box: blocks[0].box, originalText: "同")])
            throw SelectionCheckFailure.failed("Coincident bubbles were accepted.")
        } catch RegionPartitionError.duplicateRegions { }
        do {
            _ = try ImageRegionSelection.partitions(TextBox(x: 0, y: 0, width: 0, height: 1), blocks: [])
            throw SelectionCheckFailure.failed("Empty-width partition was accepted.")
        } catch RegionPartitionError.invalidBounds { }
    }
    private static func require(_ value: Bool, _ message: String) throws { if !value { throw SelectionCheckFailure.failed(message) } }
}
private enum SelectionCheckFailure: Error { case failed(String) }
