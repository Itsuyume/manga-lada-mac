import AppKit
import MangaLadaCore
import SwiftUI

@MainActor
public final class ReadingSettings: ObservableObject {
    @Published public var layout: PageLayout { didSet { defaults.set(layout.rawValue, forKey: prefix + ".layout") } }
    @Published public var direction: ReadingDirection { didSet { defaults.set(direction.rawValue, forKey: prefix + ".direction") } }
    @Published public var fit: PageFit = .page
    @Published public var zoom: Double = 1
    @Published public var showThumbnails = false
    @Published public var coverAlone = true
    private let defaults: UserDefaults
    private let prefix: String
    private let zoomRange = 0.4...4.0
    private var magnificationStart: Double?

    public init(prefix: String, defaults: UserDefaults = .standard) {
        self.prefix = prefix; self.defaults = defaults
        layout = PageLayout(rawValue: defaults.string(forKey: prefix + ".layout") ?? "single") ?? .single
        direction = ReadingDirection(rawValue: defaults.string(forKey: prefix + ".direction") ?? "rightToLeft") ?? .rightToLeft
    }
    public func navigation(count: Int) -> PageNavigation {
        PageNavigation(count: count, layout: layout, direction: direction, coverAlone: coverAlone)
    }
    public var zoomPercent: Int { Int((zoom * 100).rounded()) }
    public var canZoomIn: Bool { zoom < zoomRange.upperBound }
    public var canZoomOut: Bool { zoom > zoomRange.lowerBound }
    public func zoomIn() { endMagnification(); zoom = clampedZoom(((zoom + 0.2) * 100).rounded() / 100) }
    public func zoomOut() { endMagnification(); zoom = clampedZoom(((zoom - 0.2) * 100).rounded() / 100) }
    public func updateMagnification(_ factor: Double) throws {
        guard factor.isFinite, factor > 0, zoom.isFinite, zoom > 0 else { throw ReadingGestureError.invalidMagnification }
        let start = magnificationStart ?? zoom
        magnificationStart = start
        zoom = clampedZoom(start * factor)
    }
    public func endMagnification() { magnificationStart = nil }
    private func clampedZoom(_ value: Double) -> Double { min(zoomRange.upperBound, max(zoomRange.lowerBound, value)) }
    public func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
}

public enum ReadingGestureError: LocalizedError {
    case invalidMagnification
    public var errorDescription: String? { "확대·축소 제스처 값이 올바르지 않습니다." }
}

public enum MangaUI {
    public static let canvas = Color(red: 0.14, green: 0.15, blue: 0.17)
    public static let accent = Color(red: 0.20, green: 0.39, blue: 0.75)
}

public struct AppBrand: View {
    let title: String
    let symbol: String
    public init(_ title: String, symbol: String) { self.title = title; self.symbol = symbol }
    public var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(MangaUI.accent)
            Text(title).font(.system(size: 16, weight: .semibold))
        }.fixedSize()
    }
}
