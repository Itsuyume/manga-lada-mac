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

    func connectedLightRegion(around rect: NSRect, imageSize: NSSize, flow: TextFlow) -> NSRect? {
        let searchRect = clamped(searchRect(around: rect, imageSize: imageSize, flow: flow), imageSize: imageSize)
        guard searchRect.width >= 8, searchRect.height >= 8 else {
            return nil
        }

        let step = CGFloat(max(6, min(14, Int(min(imageSize.width, imageSize.height) / 550))))
        let columns = max(1, Int(ceil(searchRect.width / step)))
        let rows = max(1, Int(ceil(searchRect.height / step)))
        let count = columns * rows
        var lightCells = Array(repeating: false, count: count)
        var queue: [Int] = []
        let seedRect = rect.insetBy(dx: -step, dy: -step)

        for row in 0..<rows {
            for column in 0..<columns {
                let point = NSPoint(
                    x: searchRect.minX + (CGFloat(column) + 0.5) * step,
                    y: searchRect.minY + (CGFloat(row) + 0.5) * step
                )
                let index = row * columns + column
                guard isLight(at: point) else {
                    continue
                }
                lightCells[index] = true
                if seedRect.contains(point) {
                    queue.append(index)
                }
            }
        }

        guard !queue.isEmpty else {
            return nil
        }

        return connectedComponentRect(
            lightCells: lightCells,
            queue: queue,
            columns: columns,
            rows: rows,
            step: step,
            searchRect: searchRect,
            seedRect: rect
        )
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

    private func connectedComponentRect(
        lightCells: [Bool],
        queue initialQueue: [Int],
        columns: Int,
        rows: Int,
        step: CGFloat,
        searchRect: NSRect,
        seedRect: NSRect
    ) -> NSRect? {
        let count = columns * rows
        var queue = initialQueue
        var visited = Array(repeating: false, count: count)
        var cursor = 0
        var minColumn = columns
        var maxColumn = 0
        var minRow = rows
        var maxRow = 0
        var componentCount = 0

        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            guard index >= 0, index < count, lightCells[index], !visited[index] else {
                continue
            }

            visited[index] = true
            componentCount += 1
            let row = index / columns
            let column = index % columns
            minColumn = min(minColumn, column)
            maxColumn = max(maxColumn, column)
            minRow = min(minRow, row)
            maxRow = max(maxRow, row)

            appendNeighbors(of: index, column: column, row: row, columns: columns, rows: rows, to: &queue)
        }

        guard componentCount >= 4, minColumn <= maxColumn, minRow <= maxRow else {
            return nil
        }

        let detectedRect = NSRect(
            x: searchRect.minX + CGFloat(minColumn) * step,
            y: searchRect.minY + CGFloat(minRow) * step,
            width: CGFloat(maxColumn - minColumn + 1) * step,
            height: CGFloat(maxRow - minRow + 1) * step
        )
        guard detectedRect.width >= seedRect.width * 0.60,
              detectedRect.height >= seedRect.height * 0.60 else {
            return nil
        }

        let coverage = (detectedRect.width * detectedRect.height) / max(1, searchRect.width * searchRect.height)
        if coverage > 0.88,
           (detectedRect.width > seedRect.width * 2.8 || detectedRect.height > seedRect.height * 2.8) {
            return nil
        }
        return clamped(detectedRect, imageSize: imageSize)
    }

    private func appendNeighbors(
        of index: Int,
        column: Int,
        row: Int,
        columns: Int,
        rows: Int,
        to queue: inout [Int]
    ) {
        if column > 0 {
            queue.append(index - 1)
        }
        if column + 1 < columns {
            queue.append(index + 1)
        }
        if row > 0 {
            queue.append(index - columns)
        }
        if row + 1 < rows {
            queue.append(index + columns)
        }
    }

    private func searchRect(around rect: NSRect, imageSize: NSSize, flow: TextFlow) -> NSRect {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        switch flow {
        case .horizontal:
            horizontalPadding = max(72, rect.width * 0.65)
            verticalPadding = max(60, rect.height * 0.28)
        case .vertical:
            horizontalPadding = max(54, rect.width * 1.25)
            verticalPadding = max(48, rect.height * 0.30)
        }
        return rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding)
    }

    private func isLight(at point: NSPoint) -> Bool {
        let pixelX = max(0, min(bitmap.pixelsWide - 1, Int((point.x / imageSize.width) * CGFloat(bitmap.pixelsWide))))
        let yFromTop = imageSize.height - point.y
        let pixelY = max(0, min(bitmap.pixelsHigh - 1, Int((yFromTop / imageSize.height) * CGFloat(bitmap.pixelsHigh))))
        guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB) else {
            return false
        }

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
