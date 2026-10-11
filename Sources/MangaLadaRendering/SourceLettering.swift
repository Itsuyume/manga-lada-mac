import AppKit
import MangaLadaCore

/// A bounded source-pixel measurement. Text meaning and manual choices belong to the style policy.
struct SourceLettering {
    private let bitmap: NSBitmapImageRep
    private let cleaned: NSBitmapImageRep?
    init?(image: NSImage, cleanedImage: NSImage? = nil) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        bitmap = NSBitmapImageRep(cgImage: cgImage)
        if let cleanedImage {
            guard let clean = cleanedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            cleaned = NSBitmapImageRep(cgImage: clean)
        } else { cleaned = nil }
    }

    func colors(for block: TextBlock) -> SourceLetteringPalette? {
        guard let cleaned, cleaned.pixelsWide == bitmap.pixelsWide, cleaned.pixelsHigh == bitmap.pixelsHigh else { return nil }
        let box = block.userDefinedBounds ?? block.box
        let left = max(0, Int(floor(box.x * Double(bitmap.pixelsWide))))
        let top = max(0, Int(floor(box.y * Double(bitmap.pixelsHigh))))
        let right = min(bitmap.pixelsWide, Int(ceil((box.x + box.width) * Double(bitmap.pixelsWide))))
        let bottom = min(bitmap.pixelsHigh, Int(ceil((box.y + box.height) * Double(bitmap.pixelsHigh))))
        guard right - left >= 4, bottom - top >= 4 else { return nil }
        let step = max(1, (max(right - left, bottom - top) + 255) / 256)
        var samples = SourceLetteringColorSamples(), count = 0
        for y in stride(from: top, to: bottom, by: step) {
            for x in stride(from: left, to: right, by: step) {
                guard let original = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let clean = cleaned.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                count += 1; samples.add(source: original, cleaned: clean)
            }
        }
        return samples.palette(sampleCount: count)
    }

    func strokeRatio(for block: TextBlock) -> Double? {
        let box = block.userDefinedBounds ?? block.box
        let x = max(0, Int(box.x * Double(bitmap.pixelsWide)))
        let y = max(0, Int(box.y * Double(bitmap.pixelsHigh)))
        let width = min(bitmap.pixelsWide - x, Int(box.width * Double(bitmap.pixelsWide)))
        let height = min(bitmap.pixelsHigh - y, Int(box.height * Double(bitmap.pixelsHigh)))
        guard width >= 4, height >= 4, let fontSize = block.detectedFontSize, fontSize > 0 else { return nil }
        let step = max(1, (max(width, height) + 255) / 256)
        let columns = width / step, rows = height / step
        var ink = [Bool](repeating: false, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                ink[row * columns + column] = sourceInk(x: x + column * step, y: y + row * step)
            }
        }
        let measurements = isolatedInk(ink, width: columns, height: rows)
        guard measurements.area >= 12, measurements.perimeter > 0 else { return nil }
        return 2 * Double(measurements.area * step) / Double(measurements.perimeter) / fontSize
    }

    private func sourceInk(x: Int, y: Int) -> Bool {
        guard let source = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
        if let cleaned, cleaned.pixelsWide == bitmap.pixelsWide, cleaned.pixelsHigh == bitmap.pixelsHigh,
           let clean = cleaned.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
            return SourceLetteringColorSamples.isChanged(source: source, cleaned: clean)
        }
        return max(source.redComponent, source.greenComponent, source.blueComponent) < 0.25
    }

    private func isolatedInk(_ ink: [Bool], width: Int, height: Int) -> (area: Int, perimeter: Int) {
        var visited = [Bool](repeating: false, count: ink.count)
        var area = 0, perimeter = 0
        for start in ink.indices where ink[start] && !visited[start] {
            var queue = [start], cursor = 0, boundary = false, edgeCount = 0
            visited[start] = true
            while cursor < queue.count {
                let index = queue[cursor], x = index % width, y = index / width
                cursor += 1
                if x == 0 || y == 0 || x == width - 1 || y == height - 1 { boundary = true }
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { edgeCount += 1; continue }
                    let next = ny * width + nx
                    guard ink[next] else { edgeCount += 1; continue }
                    if !visited[next] { visited[next] = true; queue.append(next) }
                }
            }
            guard !boundary, queue.count >= 3, queue.count < ink.count / 4 else { continue }
            area += queue.count; perimeter += edgeCount
        }
        return (area, perimeter)
    }
}

@MainActor
enum LetteringStylePolicy {
    static func usesSource(_ block: TextBlock, typography: MangaTypography) -> Bool {
        (block.effectStyleID ?? (block.textKind == .soundEffect ? typography.effectStyleID : nil)) == "automatic"
    }
    static func colors(_ block: TextBlock, typography: MangaTypography, source: SourceLettering?) -> SourceLetteringPalette? {
        guard usesSource(block, typography: typography) else { return nil }
        return source?.colors(for: block)
    }
    static func selected(_ block: TextBlock, typography: MangaTypography, source: SourceLettering?) throws -> SoundEffectStyle? {
        let identifier = block.effectStyleID ?? (block.textKind == .soundEffect ? typography.effectStyleID : nil)
        guard let identifier, identifier != "custom" else { return nil }
        try SoundEffectFonts.registerBundledFonts()
        let library = try SoundEffectLibrary.standard()
        if identifier != "automatic" { return try library.style(id: identifier) }
        if let ratio = source?.strokeRatio(for: block), ratio < 0.085 { return try library.style(id: "handwritten") }
        return try library.automaticStyle(original: block.originalText, translated: block.translatedText)
    }

    static func expressiveDialogue(_ block: TextBlock, pageFontSize: Double) -> Bool {
        guard block.textKind == .dialogue, block.balloonShape != nil, let size = block.detectedFontSize,
              size > pageFontSize * 1.7, block.originalText.count <= 18 else { return false }
        return block.originalText.contains("!") || block.originalText.contains("！")
    }
}
