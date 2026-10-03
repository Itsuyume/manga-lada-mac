import Foundation

public enum PageLayout: String, Codable, CaseIterable, Sendable {
    case single, double, continuous
    public var label: String {
        switch self { case .single: "한 페이지"; case .double: "두 페이지"; case .continuous: "세로 스크롤" }
    }
}

public enum ReadingDirection: String, Codable, CaseIterable, Sendable {
    case rightToLeft, leftToRight
    public var label: String { self == .rightToLeft ? "오른쪽 → 왼쪽" : "왼쪽 → 오른쪽" }
}

public enum PageFit: String, Codable, CaseIterable, Sendable {
    case page, width
    public var label: String { self == .page ? "페이지 맞춤" : "너비 맞춤" }
}

/// Logical page order is always ascending. Only display order follows reading direction.
public struct PageNavigation: Sendable {
    public let count: Int
    public var layout: PageLayout
    public var direction: ReadingDirection
    public var coverAlone: Bool
    public init(count: Int, layout: PageLayout = .single, direction: ReadingDirection = .rightToLeft, coverAlone: Bool = true) {
        self.count = max(0, count); self.layout = layout; self.direction = direction; self.coverAlone = coverAlone
    }
    public func spread(at index: Int) -> [Int] {
        guard (0..<count).contains(index) else { return [] }
        guard layout == .double, !(coverAlone && index == 0) else { return [index] }
        let offset = coverAlone ? 1 : 0
        let first = offset + ((index - offset) / 2) * 2
        return Array(first..<min(first + 2, count))
    }
    public func displayedPages(at index: Int) -> [Int] {
        let pages = spread(at: index)
        return direction == .rightToLeft ? pages.reversed() : pages
    }
    public func next(from index: Int) -> Int {
        guard let last = spread(at: index).last else { return 0 }
        return last + 1 < count ? last + 1 : index
    }
    public func previous(from index: Int) -> Int {
        guard let first = spread(at: index).first else { return 0 }
        guard first > 0 else { return index }
        return spread(at: max(0, first - 1)).first ?? 0
    }
}
