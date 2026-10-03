import Foundation
import ImageIO
import MangaLadaCore
import UniformTypeIdentifiers

enum GraphicalTitleRecognition {
    static func repair(in url: URL, blocks: [TextBlock]) async throws -> [TextBlock] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard image.width <= 800, image.width > image.height else { return blocks }
        var resolved = blocks
        for index in blocks.indices {
            let block = blocks[index]
            let rect = CGRect(x: block.box.x * Double(image.width), y: block.box.y * Double(image.height),
                              width: block.box.width * Double(image.width), height: block.box.height * Double(image.height))
            guard block.sourceIsVertical == true, rect.height > rect.width * 4 else { continue }
            let cropRect = rect.insetBy(dx: -6, dy: -CGFloat(block.detectedFontSize ?? 16))
                .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
            guard let crop = image.cropping(to: cropRect) else { throw CocoaError(.fileReadCorruptFile) }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(destination, crop, nil)
            guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
            resolved[index].originalText = try await OllamaOpticalTextReader().recognize(data as Data)
            resolved[index].textKind = .title
        }
        return resolved
    }
}
