import AppKit

struct SourceLetteringPalette {
    let fill: NSColor
    let outline: NSColor
}

/// Only pixels changed by source erasure may describe the lettering's colour.
/// Unchanged clothing, paper and decorations are never colour evidence.
struct SourceLetteringColorSamples {
    private struct Bucket {
        var count = 0
        var red = 0.0, green = 0.0, blue = 0.0
        mutating func add(_ color: NSColor) {
            count += 1
            red += color.redComponent; green += color.greenComponent; blue += color.blueComponent
        }
        mutating func merge(_ other: Bucket) {
            count += other.count; red += other.red; green += other.green; blue += other.blue
        }
        var color: NSColor {
            NSColor(deviceRed: red / Double(count), green: green / Double(count), blue: blue / Double(count), alpha: 1)
        }
    }
    private var buckets: [Int: Bucket] = [:]
    private var changed = 0, dark = 0, light = 0

    static func isChanged(source: NSColor, cleaned: NSColor) -> Bool {
        let delta = max(abs(source.redComponent - cleaned.redComponent),
                        abs(source.greenComponent - cleaned.greenComponent), abs(source.blueComponent - cleaned.blueComponent))
        return delta >= 0.18 && source.alphaComponent >= 0.95 && cleaned.alphaComponent >= 0.95
    }

    mutating func add(source: NSColor, cleaned: NSColor) {
        guard Self.isChanged(source: source, cleaned: cleaned) else { return }
        changed += 1
        if max(source.redComponent, source.greenComponent, source.blueComponent) < 0.20 { dark += 1 }
        if min(source.redComponent, source.greenComponent, source.blueComponent) > 0.80 { light += 1 }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        guard saturation >= 0.28, brightness >= 0.30 else { return }
        buckets[Int(hue * 24) % 24, default: Bucket()].add(source)
    }

    func palette(sampleCount: Int) -> SourceLetteringPalette? {
        // Tight OCR bounds can contain mostly bold glyphs. A near-solid changed
        // rectangle is still background evidence, rather than separated lettering.
        guard changed >= 12, changed <= sampleCount * 9 / 10 else { return nil }
        let coloured = buckets.values.reduce(0) { $0 + $1.count }
        let candidates = buckets.keys.sorted().map { key -> Bucket in
            var combined = Bucket()
            for neighbor in [(key + 23) % 24, key, (key + 1) % 24] {
                if let bucket = buckets[neighbor] { combined.merge(bucket) }
            }
            return combined
        }
        guard let dominant = candidates.max(by: { $0.count < $1.count }), dominant.count >= 12,
              Double(dominant.count) >= Double(coloured) * 0.65,
              Double(dominant.count) >= Double(changed) * 0.28 else { return nil }
        let fill = dominant.color
        let luminance = 0.2126 * fill.redComponent + 0.7152 * fill.greenComponent + 0.0722 * fill.blueComponent
        let outline: NSColor = dark + light >= 4 ? (dark >= light ? .black : .white) : (luminance >= 0.45 ? .black : .white)
        return SourceLetteringPalette(fill: fill, outline: outline)
    }
}
