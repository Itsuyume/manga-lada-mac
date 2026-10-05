import Foundation

/// Horizontal OCR reconciliation changes source wording only; original geometry owns placement.
public enum JapaneseHorizontalOCR {
    public static func canRefine(_ block: TextBlock) -> Bool {
        let angle = block.rotationDegrees ?? 0
        return !block.preservesOriginalArtwork && block.sourceIsVertical == false && block.translatedText.isEmpty
            && block.userDefinedBounds == nil && block.userDefinedTextKind != true
            && block.userDefinedOriginalText != true
            && block.textKind != .soundEffect && block.textKind != .title
            && ImageRegionSelection.validates(block.box) && block.box.width >= block.box.height * 1.5
            && angle.isFinite && abs(angle) <= 5
    }
    public static func reconcile(_ blocks: [TextBlock], observations: [TextBlock]) -> [TextBlock] {
        let candidates = observations.filter {
            $0.confidence.isFinite && (0.5...1).contains($0.confidence) && ImageRegionSelection.validates($0.box)
                && $0.box.width >= $0.box.height * 1.5 && TextLanguageDetector.containsJapanese($0.originalText)
        }
        return blocks.map { block in
            guard canRefine(block) else { return block }
            let lines = candidates.filter { candidate in
                matches(candidate.box, block.box) && blocks.filter { matches(candidate.box, $0.box) }.count == 1
            }.sorted { $0.box.y < $1.box.y }
            guard let first = lines.first else { return block }
            let extent = lines.dropFirst().reduce(first.box) { $0.union($1.box) }
            guard extent.intersectionArea(with: block.box) / block.box.area >= 0.65,
                  extent.width >= block.box.width * 0.75, extent.width <= block.box.width * 1.25,
                  extent.height <= block.box.height * 2,
                  zip(lines, lines.dropFirst()).allSatisfy({ $1.box.y >= $0.box.y + $0.box.height * 0.35 }) else { return block }
            var refined = block
            refined.originalText = lines.map { $0.originalText.trimmingCharacters(in: .whitespacesAndNewlines) }.joined()
            return refined
        }
    }
    private static func matches(_ observation: TextBox, _ source: TextBox) -> Bool {
        guard ImageRegionSelection.validates(source), ImageRegionSelection.containsCenter(source, of: observation) else { return false }
        let overlap = observation.intersectionArea(with: source)
        // Detectors may disagree on line height. Full source coverage is also
        // evidence of a match; the combined extent and uniqueness checks still apply.
        return overlap / observation.area >= 0.55 || overlap / source.area >= 0.9
    }
}
