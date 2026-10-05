import AppKit

extension MangaLadaRenderingChecks {
    @MainActor
    static func imagePixels(_ image: NSImage) throws -> [UInt32] {
        guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { throw CocoaError(.coderReadCorrupt) }
        return (0..<bitmap.pixelsHigh).flatMap { y in (0..<bitmap.pixelsWide).map { x in
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            let components = [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
            return components.reduce(UInt32(0)) { ($0 << 8) | UInt32(($1 * 255).rounded()) }
        } }
    }
}
