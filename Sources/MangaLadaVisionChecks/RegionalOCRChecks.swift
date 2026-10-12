import Foundation
import MangaLadaCore
import MangaLadaVision

enum RegionalOCRChecks {
    static func run(image: URL) async throws {
        let service = VisionOCRService()
        let region = TextBox(x: 0.05, y: 0.2, width: 0.9, height: 0.6)
        let blocks = try await service.recognizeText(in: image, sourceLanguage: .english, regions: [region])
        try require(blocks.count == 1 && blocks[0].originalText == "HELLO WORLD", "Regional OCR duplicated or lost source text")
        try require(blocks[0].box.x > 0.1 && blocks[0].box.x < 0.3 && blocks[0].box.y > 0.3 && blocks[0].box.y < 0.7,
                    "Vision ROI coordinates were not projected into the page")
        let emptyRegion = TextBox(x: 0, y: 0, width: 0.1, height: 0.1)
        let retained = try await service.recognizeText(in: image, sourceLanguage: .english, regions: [emptyRegion])
        try require(retained.map(\.originalText) == ["HELLO WORLD"], "Empty regional reading suppressed the full-page reading")
        for invalid in [TextBox(x: -0.1, y: 0, width: 0.1, height: 0.1), TextBox(x: 0, y: 0, width: .nan, height: 0.1)] {
            do {
                _ = try await service.recognizeText(in: image, sourceLanguage: .english, regions: [invalid])
                throw Failure.failed("Invalid OCR search region was accepted")
            } catch OCRServiceError.invalidRegions { }
        }
        do {
            _ = try await service.recognizeText(in: image, sourceLanguage: .english, regions: Array(repeating: region, count: 81))
            throw Failure.failed("Unbounded regional OCR was accepted")
        } catch OCRServiceError.invalidRegions { }
        let task = Task { try await service.recognizeText(in: image, sourceLanguage: .english, regions: Array(repeating: region, count: 80)) }
        task.cancel()
        do { _ = try await task.value; throw Failure.failed("Cancelled regional OCR returned success") }
        catch is CancellationError { }
        let outside = TextBox(x: -0.02, y: 0.1, width: 1.03, height: 0.8)
        let projected = VisionRegionRecognition.project(outside, into: region)
        try require(projected != nil && abs((projected?.x ?? -1) - region.x) < 0.000001
                    && abs((projected?.width ?? -1) - region.width) < 0.000001
                    && abs((projected?.height ?? -1) - 0.8*region.height) < 0.000001,
                    "Vision edge overshoot escaped the selected region")
        print("Regional native OCR passed: real OCR, coordinate projection, no duplicate, empty/invalid/budget/cancelled requests")
        try checkCombination()
    }

    private static func checkCombination() throws {
        let title = TextBlock(box: .init(x: 0.1, y: 0.02, width: 0.4, height: 0.09), originalText: "LITTLE NEMO")
        let fragment = TextBlock(box: .init(x: 0.3, y: 0.03, width: 0.08, height: 0.05), originalText: "EMO")
        let combined = VisionRegionRecognition.combine(global: [title], regional: [(fragment.box, [fragment])])
        try require(combined == [title], "A clipped title fragment duplicated its full source region")
        let left = TextBlock(box: .init(x: 0.02, y: 0.5, width: 0.45, height: 0.02), originalText: "FIRST PANEL")
        let right = TextBlock(box: .init(x: 0.53, y: 0.5, width: 0.45, height: 0.02), originalText: "SECOND PANEL")
        let mixed = TextBlock(box: left.box.union(right.box), originalText: "TWO PANELS MIXED")
        let regions = [(TextBox(x: 0, y: 0.48, width: 0.5, height: 0.06), [left]),
                       (TextBox(x: 0.5, y: 0.48, width: 0.5, height: 0.06), [right])]
        try require(Set(VisionRegionRecognition.combine(global: [mixed], regional: regions).map(\.id)) == Set([left.id, right.id]),
                    "A mixed full-page line survived independent paragraph readings")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }
    private enum Failure: Error { case failed(String) }
}
