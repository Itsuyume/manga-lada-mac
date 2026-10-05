import AppKit
import MangaLadaCore
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    @MainActor
    static func checkAdjacentBalloons(in root: URL) throws {
        let image = NSImage(size: NSSize(width: 1200, height: 900))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 900).fill(); image.unlockFocus()
        let short = TextBlock(box: TextBox(x: 0.2875, y: 0.22, width: 0.025, height: 0.042),
                              originalText: "あの", translatedText: "저기", detectedFontSize: 30, textKind: .dialogue)
        let enclosure = TextBox(x: 0.155, y: 0.16, width: 0.23, height: 0.43)
        let long = TextBlock(box: TextBox(x: 0.225, y: 0.313, width: 0.033, height: 0.211),
                             originalText: "少し休んでもいい？", translatedText: "조금 쉬어도 될까?", detectedFontSize: 30,
                             textKind: .dialogue, balloonShape: placementRectangle(enclosure))
        let originals = [short, long]
        let actual = try TranslatedImageRenderer().render(image: image, blocks: originals, backgroundStyle: .none)
        var reserved = long
        let divider = (short.box.y + short.box.height + long.box.y) / 2
        reserved.balloonShape = long.balloonShape?.clipped(to: TextBox(x: 0, y: divider, width: 1, height: 1 - divider))
        let expected = try TranslatedImageRenderer().render(image: image, blocks: [short, reserved], backgroundStyle: .none)
        try require(actual.tiffRepresentation == expected.tiffRepresentation, "A missed short contour still shared the neighboring balloon's text area.")
        try require(originals == [short, long], "Rendering changed source geometry or text.")
        let reversed = try TranslatedImageRenderer().render(image: image, blocks: originals.reversed(), backgroundStyle: .none)
        try require(actual.tiffRepresentation == reversed.tiffRepresentation, "Adjacent balloon placement depended on draw order.")
        let source = root.appendingPathComponent("adjacent-source.png"), output = root.appendingPathComponent("adjacent-result.png")
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: source)
        let page = PageTranslation(imageURL: source, imageFingerprint: "adjacent", sourceLanguage: .japanese, targetLanguage: .korean, blocks: originals)
        _ = try TranslatedImageRenderer().writePNG(sourceImageURL: source, translation: page, destinationURL: output, backgroundStyle: .none)
        try checkOverlappingSourceRejected(page: page, source: source, output: output)
        let tiny = TextBlock(box: TextBox(x: 0.6, y: 0.4, width: 0.015, height: 0.012), originalText: "こんにちは",
                             translatedText: "안녕하세요", detectedFontSize: 30, textKind: .dialogue)
        do {
            _ = try TranslatedImageRenderer().render(image: image, blocks: [tiny], backgroundStyle: .none)
            try require(false, "Unreadable tiny text was saved as a successful translation.")
        } catch TranslatedImageRenderError.textDoesNotFit { }
        print("Adjacent balloons passed: missing contour, separate occupied areas, order independence, tiny text and failed-save preservation")
    }

    @MainActor
    private static func checkOverlappingSourceRejected(page: PageTranslation, source: URL, output: URL) throws {
        let sourceBytes = try Data(contentsOf: source), outputBytes = try Data(contentsOf: output)
        var collision = page
        collision.blocks[1].box = collision.blocks[0].box
        do {
            _ = try TranslatedImageRenderer().writePNG(sourceImageURL: source, translation: collision,
                                                       destinationURL: output, backgroundStyle: .none)
            try require(false, "Overlapping source areas silently overwrote a saved image.")
        } catch TranslatedImageRenderError.overlappingRegions { }
        try require(try Data(contentsOf: output) == outputBytes && Data(contentsOf: source) == sourceBytes,
                    "An overlapping-region failure modified the source or previous image.")
    }

    private static func placementRectangle(_ box: TextBox) -> BalloonShape {
        BalloonShape(bounds: box, rows: (0...192).map { index in
            BalloonShapeRow(y: box.y + box.height * Double(index) / 192, left: box.x, right: box.x + box.width)
        })
    }
}
