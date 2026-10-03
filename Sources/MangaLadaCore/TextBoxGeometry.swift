extension TextBox {
    var area: Double { width * height }
    func intersectionArea(with other: TextBox) -> Double {
        let overlapWidth = max(0, min(x + width, other.x + other.width) - max(x, other.x))
        let overlapHeight = max(0, min(y + height, other.y + other.height) - max(y, other.y))
        return overlapWidth * overlapHeight
    }
    func union(_ other: TextBox) -> TextBox {
        let left = min(x, other.x), top = min(y, other.y)
        return TextBox(x: left, y: top, width: max(x + width, other.x + other.width) - left,
                       height: max(y + height, other.y + other.height) - top)
    }
}
