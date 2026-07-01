import AppKit
import Foundation

let outputURL: URL
if CommandLine.arguments.count >= 2 {
    outputURL = URL(filePath: CommandLine.arguments[1])
} else {
    outputURL = URL(filePath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("AppIcon.icns")
}

let workURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("MangaLadaIcon.iconset")
try? FileManager.default.removeItem(at: workURL)
try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

let iconSpecs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for spec in iconSpecs {
    let image = drawIcon(pixels: spec.pixels)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.renderFailed(spec.name)
    }
    try pngData.write(to: workURL.appendingPathComponent(spec.name), options: .atomic)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let process = Process()
process.executableURL = URL(filePath: "/usr/bin/iconutil")
process.arguments = [
    "--convert",
    "icns",
    "--output",
    outputURL.path,
    workURL.path
]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw IconError.iconutilFailed(process.terminationStatus)
}

func drawIcon(pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    let scale = CGFloat(pixels) / 1024

    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(origin: .zero, size: size)
    let background = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.30, alpha: 1)
    ])
    background?.draw(in: canvas, angle: 135)

    let inset = 96 * scale
    let card = NSBezierPath(
        roundedRect: canvas.insetBy(dx: inset, dy: inset),
        xRadius: 150 * scale,
        yRadius: 150 * scale
    )
    NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.88, alpha: 1).setFill()
    card.fill()

    let shadow = NSBezierPath(
        roundedRect: NSRect(x: 224 * scale, y: 176 * scale, width: 576 * scale, height: 520 * scale),
        xRadius: 56 * scale,
        yRadius: 56 * scale
    )
    NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.08, alpha: 0.12).setFill()
    shadow.fill()

    let bubble = NSBezierPath(
        roundedRect: NSRect(x: 196 * scale, y: 232 * scale, width: 632 * scale, height: 468 * scale),
        xRadius: 64 * scale,
        yRadius: 64 * scale
    )
    NSColor.white.setFill()
    bubble.fill()

    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: 380 * scale, y: 236 * scale))
    tail.line(to: NSPoint(x: 306 * scale, y: 134 * scale))
    tail.line(to: NSPoint(x: 488 * scale, y: 236 * scale))
    tail.close()
    NSColor.white.setFill()
    tail.fill()

    let teal = NSColor(calibratedRed: 0.05, green: 0.58, blue: 0.62, alpha: 1)
    teal.setFill()
    NSBezierPath(ovalIn: NSRect(x: 704 * scale, y: 656 * scale, width: 92 * scale, height: 92 * scale)).fill()

    drawCentered("文", rect: NSRect(x: 232 * scale, y: 346 * scale, width: 276 * scale, height: 240 * scale), size: 178 * scale)
    drawCentered("가", rect: NSRect(x: 520 * scale, y: 346 * scale, width: 276 * scale, height: 240 * scale), size: 178 * scale)

    return image
}

func drawCentered(_ text: String, rect: NSRect, size: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: .heavy),
        .foregroundColor: NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.11, alpha: 1),
        .paragraphStyle: paragraph
    ]
    text.draw(in: rect, withAttributes: attributes)
}

enum IconError: LocalizedError {
    case renderFailed(String)
    case iconutilFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .renderFailed(let name):
            return "Failed to render icon layer: \(name)"
        case .iconutilFailed(let status):
            return "iconutil failed with status \(status)"
        }
    }
}
