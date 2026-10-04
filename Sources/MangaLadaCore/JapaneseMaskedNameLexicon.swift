import Foundation

/// Only catalogued names with one missing letter and an adjacent usage cue are expanded.
/// No OCR source or saved review is changed; this result is for the translation request.
enum JapaneseMaskedNameLexicon {
    struct Resolution {
        let text: String
        let terms: [String: String]
        var koreanNames: [String] { Array(Set(terms.values)).sorted() }
    }
    private struct Entry {
        let japanese: String
        let korean: String
    }
    private struct Match {
        let range: Range<String.Index>
        let entry: Entry
    }
    private static let entries = [
        Entry(japanese: "スマブラ", korean: "스매시브라더스"),
        Entry(japanese: "ポケモン", korean: "포켓몬"),
        Entry(japanese: "カービィ", korean: "커비"),
        Entry(japanese: "マリオ", korean: "마리오")
    ]
    private static let usageCues = ["しよう", "やろう", "をしよう", "をやろう", "で対戦", "で遊", "のゲーム",
                                    "をプレイ", "の大会", "の映画", "のぬいぐるみ"]

    static func resolve(_ source: String, maskCharacters: String) -> Resolution {
        guard source.contains(where: { maskCharacters.contains($0) }) else {
            return Resolution(text: source, terms: [:])
        }
        let matches = entries.flatMap { matches(in: source, entry: $0, maskCharacters: maskCharacters) }
        // Future catalog additions must not choose between overlapping or ambiguous names.
        let unique = matches.filter { match in
            matches.filter { $0.range.overlaps(match.range) }.count == 1
        }.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var text = "", cursor = source.startIndex
        for match in unique {
            text += source[cursor..<match.range.lowerBound] + match.entry.japanese
            cursor = match.range.upperBound
        }
        text += source[cursor...]
        let terms = Dictionary(unique.map { ($0.entry.japanese, $0.entry.korean) }, uniquingKeysWith: { first, _ in first })
        return Resolution(text: text, terms: terms)
    }

    private static func matches(in source: String, entry: Entry, maskCharacters: String) -> [Match] {
        let letters = entry.japanese.map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard letters.count >= 3 else { return [] }
        var result: [Match] = []
        for index in letters.indices {
            var spelling = letters
            spelling[index] = "[\(maskCharacters)]"
            let boundary = "[\\p{Katakana}ー\(maskCharacters)]"
            let pattern = "(?<!\(boundary))" + spelling.joined() + "(?!\(boundary))"
            var search = source.startIndex..<source.endIndex
            while let range = source.range(of: pattern, options: .regularExpression, range: search) {
                if usageCues.contains(where: { source[range.upperBound...].hasPrefix($0) }) {
                    result.append(Match(range: range, entry: entry))
                }
                search = range.upperBound..<source.endIndex
            }
        }
        return result
    }
}
