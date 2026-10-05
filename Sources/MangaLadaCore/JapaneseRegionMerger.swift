import Foundation

/// Reconciles OCR coordinates with semantic sound-effect detection at one boundary.
public enum JapaneseRegionMerger {
    public static func merge(existing: [TextBlock], effects: [TextBlock], opticalCandidates: [TextBlock]) -> (blocks: [TextBlock], extras: [TextBlock], unverified: Int) {
        let candidates = opticalCandidates.filter { $0.confidence >= 0.35 && TextLanguageDetector.containsJapanese($0.originalText) }
        let grounded = effects.compactMap { effect -> TextBlock? in
            let matches = candidates.filter { normalized($0.originalText) == normalized(effect.originalText) && distance($0.box, effect.box) < 0.25 }
            guard let match = matches.min(by: { distance($0.box, effect.box) < distance($1.box, effect.box) }) else {
                return existing.contains { normalized($0.originalText) == normalized(effect.originalText) && overlaps($0.box, effect.box) } ? effect : nil
            }
            var resolved = effect; resolved.box = match.box; resolved.sourceIsVertical = match.sourceIsVertical
            resolved.confidence = match.confidence
            return resolved
        }
        var enriched = existing
        for effect in grounded {
            if let index = enriched.firstIndex(where: { overlaps(effect.box, $0.box) && normalized(effect.originalText) == normalized($0.originalText) }) {
                guard enriched[index].userDefinedTextKind != true, enriched[index].userDefinedBounds == nil,
                      enriched[index].balloonShape == nil else { continue }
                enriched[index].textKind = .soundEffect; enriched[index].rotationDegrees = effect.rotationDegrees
            }
        }
        var extras: [TextBlock] = []
        for candidate in grounded + candidates {
            guard candidate.confidence >= 0.35 && TextLanguageDetector.containsJapanese(candidate.originalText),
                  !enriched.contains(where: { overlaps(candidate.box, $0.box)
                      || (normalized($0.originalText).contains(normalized(candidate.originalText)) && distance(candidate.box, $0.box) < 0.25) }),
                  !extras.contains(where: { overlaps(candidate.box, $0.box) }) else { continue }
            extras.append(candidate)
        }
        return (enriched + extras, extras, effects.count - grounded.count)
    }
    private static func normalized(_ text: String) -> String { text.filter { !$0.isWhitespace } }
    private static func distance(_ a: TextBox, _ b: TextBox) -> Double {
        hypot(a.x + a.width / 2 - b.x - b.width / 2, a.y + a.height / 2 - b.y - b.height / 2)
    }
    private static func overlaps(_ a: TextBox, _ b: TextBox) -> Bool {
        let smaller = min(a.area, b.area)
        return smaller > 0 && a.intersectionArea(with: b) / smaller > 0.25
    }
}
