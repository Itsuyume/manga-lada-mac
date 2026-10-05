import Foundation

/// One range for UI input, saved reviews and the rendering boundary.
public enum LetteringPreferences {
    public static let scaleRange = 0.4...2.4
    public static var percentRange: ClosedRange<Double> { scaleRange.lowerBound * 100...scaleRange.upperBound * 100 }

    public static func validate(_ block: TextBlock) throws {
        if let scale = block.fontScale, !scale.isFinite || !scaleRange.contains(scale) {
            throw LetteringPreferenceError.invalidSize
        }
        if let bounds = block.textLayoutBounds, !ImageRegionSelection.validates(bounds) {
            throw LetteringPreferenceError.invalidBounds
        }
        if block.textOffset != nil, !ImageRegionSelection.validates(displayBounds(for: block)) {
            throw LetteringPreferenceError.invalidBounds
        }
    }

    public static func displayBounds(for block: TextBlock) -> TextBox {
        if block.preservesOriginalArtwork { return layoutBounds(for: block) }
        var bounds = layoutBounds(for: block)
        bounds.x += block.textOffset?.x ?? 0; bounds.y += block.textOffset?.y ?? 0
        return bounds
    }

    public static func layoutBounds(for block: TextBlock) -> TextBox {
        if block.preservesOriginalArtwork { return block.userDefinedBounds ?? block.balloonShape?.bounds ?? block.box }
        return block.textLayoutBounds ?? block.userDefinedBounds
            ?? (block.textKind == .soundEffect ? block.box : block.balloonShape?.bounds ?? block.box)
    }

    public static func moved(_ block: TextBlock, by delta: TextOffset) throws -> TextBlock {
        var moved = block
        moved.textOffset = TextOffset(x: (block.textOffset?.x ?? 0) + delta.x, y: (block.textOffset?.y ?? 0) + delta.y)
        try validate(moved)
        return moved
    }
}

public enum LetteringPreferenceError: LocalizedError {
    case invalidSize, invalidBounds
    public var errorDescription: String? {
        switch self {
        case .invalidSize: "글자 크기는 40~240% 사이의 숫자로 입력해주세요."
        case .invalidBounds: "배치 영역을 이미지 안에 지정해주세요."
        }
    }
}
