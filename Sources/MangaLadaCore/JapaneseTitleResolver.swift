import Foundation

/// Archive metadata corrects near-matching decorative title OCR, never unrelated text.
public enum JapaneseTitleResolver {
    public static func resolve(optical: String, bookTitle: String) -> String {
        let original = optical.precomposedStringWithCanonicalMapping
        let title = bookTitle.precomposedStringWithCanonicalMapping
        let left = Array(original.filter { !$0.isWhitespace })
        let right = Array(title.filter { !$0.isWhitespace })
        guard left.count >= 6, right.count >= 6, left.count <= 160, right.count <= 160,
              right.contains(where: { character in character.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) } }) else { return original }
        var row = [Int](repeating: 0, count: right.count + 1)
        for letter in left {
            var previous = 0
            for index in right.indices {
                let prior = row[index + 1]
                row[index + 1] = letter == right[index] ? previous + 1 : max(row[index], prior)
                previous = prior
            }
        }
        let similarity = Double(row[right.count]) / Double(max(left.count, right.count))
        return similarity >= 0.8 ? title : original
    }
}
