import AppKit
import MangaLadaCore

extension TranslatedImageRenderer {
    /// Reserve disjoint reading space before fitting text, including neighbors whose contour was missed.
    func balloonContainers(blocks: [TextBlock], imageSize: NSSize, detector: LightRegionDetector?) throws -> [UUID: BalloonShape] {
        let speech = blocks.filter { $0.textKind != .soundEffect && $0.textKind != .title && ($0.keepsOriginal == true || !displayText(for: $0).isEmpty) }
        let proposed = try speech.map { try balloonContainer(block: $0, imageSize: imageSize, detector: detector) }
        var result: [UUID: BalloonShape] = [:]
        for (index, block) in speech.enumerated() where block.keepsOriginal != true {
            var space = TextBox(x: 0, y: 0, width: 1, height: 1)
            for (otherIndex, other) in speech.enumerated() where index != otherIndex {
                guard proposed[index].bounds.intersectionArea(with: proposed[otherIndex].bounds) > 0 else { continue }
                guard let boundary = separatingSpace(for: block.box, from: other.box, imageSize: imageSize) else {
                    if other.keepsOriginal == true { continue }
                    throw TranslatedImageRenderError.overlappingRegions(block.id, other.id)
                }
                let left = max(space.x, boundary.x), top = max(space.y, boundary.y)
                let right = min(space.x + space.width, boundary.x + boundary.width)
                let bottom = min(space.y + space.height, boundary.y + boundary.height)
                space = TextBox(x: left, y: top, width: right - left, height: bottom - top)
            }
            guard let clipped = proposed[index].clipped(to: space) else {
                throw TranslatedImageRenderError.textDoesNotFit(block.id, displayText(for: block))
            }
            result[block.id] = clipped
        }
        return result
    }

    private func balloonContainer(block: TextBlock, imageSize: NSSize, detector: LightRegionDetector?) throws -> BalloonShape {
        if block.keepsOriginal == true {
            return block.balloonShape ?? DialogueTypesettingRules.rectangularShape(box: block.userDefinedBounds ?? block.box)
        }
        if let selected = block.textLayoutBounds ?? block.userDefinedBounds {
            guard let contour = block.balloonShape else { return DialogueTypesettingRules.rectangularShape(box: selected) }
            guard let clipped = contour.clipped(to: selected) else {
                throw TranslatedImageRenderError.textDoesNotFit(block.id, displayText(for: block))
            }
            return clipped
        }
        if let contour = block.balloonShape { return contour }
        let ink = pixelRect(for: block.box, imageSize: imageSize)
        let container = textContainerRect(fallbackRect: ink, originalTextRect: ink, imageSize: imageSize,
                                          flow: .horizontal, backgroundStyle: .none, lightRegionDetector: detector)
        let box = TextBox(x: container.minX / imageSize.width, y: 1 - container.maxY / imageSize.height,
                          width: container.width / imageSize.width, height: container.height / imageSize.height)
        return DialogueTypesettingRules.rectangularShape(box: box)
    }

    private func separatingSpace(for source: TextBox, from other: TextBox, imageSize: NSSize) -> TextBox? {
        let horizontalGap = max(other.x - source.x - source.width, source.x - other.x - other.width)
        let verticalGap = max(other.y - source.y - source.height, source.y - other.y - other.height)
        // OCR rectangles may touch at a corner even when their glyphs are separate.
        // Reject substantial overlap; bisect only the small shared edge otherwise.
        guard source.intersectionArea(with: other) <= min(source.area, other.area) * 0.25 else { return nil }
        let dx = source.x + source.width / 2 - other.x - other.width / 2
        let dy = source.y + source.height / 2 - other.y - other.height / 2
        let horizontal = horizontalGap >= 0 || verticalGap >= 0
            ? horizontalGap * imageSize.width > verticalGap * imageSize.height
            : abs(dx) * imageSize.width > abs(dy) * imageSize.height
        if horizontal {
            let edge = dx < 0 ? (source.x + source.width + other.x) / 2 : (other.x + other.width + source.x) / 2
            return TextBox(x: dx < 0 ? 0 : edge, y: 0, width: dx < 0 ? edge : 1 - edge, height: 1)
        }
        let edge = dy < 0 ? (source.y + source.height + other.y) / 2 : (other.y + other.height + source.y) / 2
        return TextBox(x: 0, y: dy < 0 ? 0 : edge, width: 1, height: dy < 0 ? edge : 1 - edge)
    }
}
