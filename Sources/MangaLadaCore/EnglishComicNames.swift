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

    /// Common words that open a sentence. Other capitalized first words may begin a name ("Silver Moon Spring is…").
    private static let sentenceOpeners: Set<String> = [
        "A", "An", "The", "This", "That", "These", "Those", "My", "Your", "Our", "Their", "His", "Her", "Its",
        "He", "She", "It", "We", "You", "They", "Me", "Us", "Him", "Them",
        "Did", "Do", "Does", "Is", "Are", "Was", "Were", "Will", "Would", "Can", "Could", "Should", "Shall", "May", "Might",
        "Must", "Have", "Has", "Had", "Don't", "Can't", "Won't", "Isn't", "Didn't", "I'm", "It's", "That's", "Let's",
        "What", "Where", "When", "Why", "How", "Who", "Which", "Whose",
        "And", "But", "Or", "So", "If", "Then", "Now", "Just", "Well", "Oh", "Hey", "Yes", "No", "Not", "Please",
        "Thank", "Thanks", "Look", "Come", "Go", "Tell", "Give", "Take", "Wait", "Stop", "Help", "Get", "Meet", "See"
    ]

    private static func candidates(in text: String) -> [String] {
        var run: [String] = [], names: [String] = []
        let titles: Set<String> = ["Majesty", "Queen", "King", "Highness", "Lord", "Lady", "Sir", "Madam"]
        func finish() {
            if (2...6).contains(run.count), !run.contains(where: titles.contains) {
                names.append(run.joined(separator: " "))
            }
            run.removeAll(keepingCapacity: true)
        }
        var sentenceStart = true
        for token in text.split(whereSeparator: \.isWhitespace) {
            let word = token.trimmingCharacters(in: .punctuationCharacters)
            // Every sentence capitalizes its first word: "Did Alice come?" names Alice, not "Did Alice".
            if sentenceStart, sentenceOpeners.contains(word) {
                finish()
            } else if word.first?.isUppercase == true && word.dropFirst().contains(where: \.isLowercase) {
                run.append(word)
            } else { finish() }
            if token.last?.isPunctuation == true { finish() }
            sentenceStart = token.last.map { ".!?…".contains($0) } ?? false
        }
        finish()
        return names
    }
}
