import Foundation

/// Optical capitalization is a prompt hint, never a replacement of source text.
enum EnglishComicNames {
    static func guidance(blocks: [TextBlock]) -> String {
        let hints = blocks.enumerated().flatMap { index, block in
            candidates(in: block.originalText).map {
                "R\(index): '\($0)' is a capitalized name. Preserve it as a Korean name (Hangul transliteration if no established name is in context), not a literal description or count."
            }
        }
        return hints.isEmpty ? "" : "Name guide (context only):\n" + hints.joined(separator: "\n")
    }

    private static func candidates(in text: String) -> [String] {
        var run: [String] = [], names: [String] = []
        let titles: Set<String> = ["Majesty", "Queen", "King", "Highness", "Lord", "Lady", "Sir", "Madam"]
        func finish() {
            if (2...6).contains(run.count), !run.contains(where: titles.contains) {
                names.append(run.joined(separator: " "))
            }
            run.removeAll(keepingCapacity: true)
        }
        for token in text.split(whereSeparator: \.isWhitespace) {
            let word = token.trimmingCharacters(in: .punctuationCharacters)
            if word.first?.isUppercase == true && word.dropFirst().contains(where: \.isLowercase) {
                run.append(word)
            } else { finish() }
            if token.last?.isPunctuation == true { finish() }
        }
        finish()
        return names
    }
}
