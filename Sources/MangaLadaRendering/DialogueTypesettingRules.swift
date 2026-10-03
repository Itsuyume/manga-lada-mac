import AppKit
import MangaLadaCore

/// One policy for all speech and narration. Source writing direction never changes Korean dialogue flow.
enum DialogueTypesettingRules {
    static let lineSpacing = 1.20
    static let sizeSteps = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5]
    static let insetRatio = 0.32
    static let centerFractions = [0.5, 0.45, 0.55, 0.4, 0.6, 0.35, 0.65, 0.3, 0.7]
    static let maximumInsetFraction = 0.06
    static func referenceWidth(_ imageSize: NSSize) -> Double { min(imageSize.width, imageSize.height * 0.75) }

    static func pageFontSize(blocks: [TextBlock], imageSize: NSSize) -> Double {
        let sizes = blocks.filter { $0.textKind != .soundEffect && $0.textKind != .title }
            .compactMap(\.detectedFontSize).filter { $0.isFinite && $0 > 0 }.sorted()
        let width = referenceWidth(imageSize)
        let median = sizes.isEmpty ? width * 0.025 : sizes[sizes.count / 2]
        let nominal = width * 0.026
        return min(64, max(16, min(nominal * 1.1, max(nominal * 0.9, median))))
    }

    static func rectangularShape(box: TextBox) -> BalloonShape {
        let rows = (0...96).map { index in
            BalloonShapeRow(y: box.y + box.height * Double(index) / 96, left: box.x, right: box.x + box.width)
        }
        return BalloonShape(bounds: box, rows: rows)
    }
}
