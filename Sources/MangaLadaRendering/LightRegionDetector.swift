import AppKit
import Foundation

struct LightRegionDetector {
    private let bitmap: NSBitmapImageRep
    private let imageSize: NSSize

    init?(image: NSImage, imageSize: NSSize) {
        var proposedRect = NSRect(origin: .zero, size: imageSize)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        self.bitmap = NSBitmapImageRep(cgImage: cgImage)
        self.imageSize = imageSize
    }

    func lightCoverage(in rect: NSRect) -> Double {
        let sampleRect = clamped(rect, imageSize: imageSize)
        guard sampleRect.width >= 4, sampleRect.height >= 4 else {
            return 0
        }

        let step = CGFloat(max(8, min(16, Int(min(imageSize.width, imageSize.height) / 480))))
        let columns = max(1, Int(ceil(sampleRect.width / step)))
        let rows = max(1, Int(ceil(sampleRect.height / step)))
        var lightCount = 0
        let totalCount = columns * rows

        for row in 0..<rows {
            for column in 0..<columns {
                let point = NSPoint(
                    x: sampleRect.minX + (CGFloat(column) + 0.5) * step,
                    y: sampleRect.minY + (CGFloat(row) + 0.5) * step
                )
                if isLight(at: point) {
                    lightCount += 1
                }
            }
        }
        return Double(lightCount) / Double(max(1, totalCount))
    }
    func medianLuminance(in rect: NSRect) -> CGFloat? {
        let samples = (0..<9).flatMap { row in
            (0..<9).compactMap { column -> CGFloat? in
                let point = NSPoint(x: rect.minX + rect.width * (CGFloat(column) + 0.5) / 9,
                                    y: rect.minY + rect.height * (CGFloat(row) + 0.5) / 9)
                guard let color = color(at: point) else { return nil }
                return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
            }
        }.sorted()
        return samples.isEmpty ? nil : samples[samples.count / 2]
    }

    func horizontalLightSpan(around rect: NSRect, maximumWidth: CGFloat) -> NSRect? {
        let center = rect.midX
        let rowCount = max(2, min(64, Int(ceil(rect.height / 4))))
        let ySamples = (0...rowCount).map { rect.minY + rect.height * CGFloat($0) / CGFloat(rowCount) }
        guard ySamples.allSatisfy({ isLight(at: NSPoint(x: center, y: $0)) }) else { return nil }
        let halfWidth = maximumWidth / 2
        var left = center, right = center
        while left > max(0, center - halfWidth), ySamples.allSatisfy({ isLight(at: NSPoint(x: left - 1, y: $0)) }) { left -= 1 }
        while right < min(imageSize.width, center + halfWidth), ySamples.allSatisfy({ isLight(at: NSPoint(x: right + 1, y: $0)) }) { right += 1 }
        guard right - left - 6 > rect.width else { return nil }
        return NSRect(x: left + 3, y: rect.minY, width: max(1, right - left - 6), height: rect.height)
    }

    func constrainedToPanel(_ proposed: NSRect, around ink: NSRect) -> NSRect {
        let samples = (0...12).map { ink.minY + ink.height * CGFloat($0) / 12 }
        let left = stride(from: Int(ink.minX), through: Int(proposed.minX), by: -1).first { isPanelRule(x: CGFloat($0), samples: samples) }
        let right = stride(from: Int(ink.maxX), through: Int(proposed.maxX), by: 1).first { isPanelRule(x: CGFloat($0), samples: samples) }
        let minX = left.map { max(proposed.minX, CGFloat($0) + 5) } ?? proposed.minX
        let maxX = right.map { min(proposed.maxX, CGFloat($0) - 5) } ?? proposed.maxX
        return NSRect(x: minX, y: proposed.minY, width: max(1, maxX - minX), height: proposed.height)
    }

    private func isPanelRule(x: CGFloat, samples: [CGFloat]) -> Bool {
        func coverage(_ column: CGFloat) -> Double {
            Double(samples.filter { point in
                guard let color = color(at: NSPoint(x: column, y: point)) else { return false }
                return max(color.redComponent, color.greenComponent, color.blueComponent) < 0.2
            }.count) / Double(samples.count)
        }
        return coverage(x) > 0.9 && coverage(x - 10) < 0.8 && coverage(x + 10) < 0.8
    }

    private func color(at point: NSPoint) -> NSColor? {
        let pixelX = max(0, min(bitmap.pixelsWide - 1, Int((point.x / imageSize.width) * CGFloat(bitmap.pixelsWide))))
        let yFromTop = imageSize.height - point.y
        let pixelY = max(0, min(bitmap.pixelsHigh - 1, Int((yFromTop / imageSize.height) * CGFloat(bitmap.pixelsHigh))))
        return bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
    }

    private func isLight(at point: NSPoint) -> Bool {
        guard let color = color(at: point) else { return false }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        guard alpha > 0.2 else {
            return false
        }

        let brightness = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let saturation = max(red, green, blue) - min(red, green, blue)
        return brightness >= 0.82 && saturation <= 0.18
    }

    private func clamped(_ rect: NSRect, imageSize: NSSize) -> NSRect {
        let minX = max(0, rect.minX)
        let minY = max(0, rect.minY)
        let maxX = min(imageSize.width, rect.maxX)
        let maxY = min(imageSize.height, rect.maxY)
        return NSRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }
}
