import Foundation
import MangaLadaCore

enum TranslationContextChecks {
    static func run() throws {
        let first = block("Wait, Mina.", "미나, 기다려.")
        let next = block("Please sit down.", "앉으세요.")
        let pages = [0: page([first]), 1: page([]), 2: page([block("BOOM", "쾅", kind: .soundEffect)]),
                     3: page([next]), 4: page([block("Future", "미래")])]
        let snapshot = pages
        let context = MangaTranslationContext.previousPages(pages, before: 4)
        try check(context.contains("미나, 기다려.") && context.contains("앉으세요."), "Blank/effect pages erased dialogue history.")
        try check(context.hasPrefix("[Page 1]") && context.contains("[Page 4]"), "Context lost chronological page markers.")
        try check(!context.contains("쾅") && !context.contains("미래") && pages == snapshot, "Context leaked effects/future data or mutated pages.")
        for (index, budget, limit) in [(0, 100, 3), (4, 0, 3), (4, 100, 0), (-1, 100, 3)] {
            try check(MangaTranslationContext.previousPages(pages, before: index, maximumCharacters: budget, maximumPages: limit).isEmpty,
                      "Invalid context bounds produced history.")
        }
        try check(MangaTranslationContext.previousPages([:], before: 4).isEmpty, "Empty input produced context.")
        let recent = MangaTranslationContext.previousPages(pages, before: 4, maximumPages: 1)
        try check(recent.contains("앉으세요.") && !recent.contains("미나"), "Useful-page limit counted blank pages.")
        let exact = MangaTranslationContext.previousPages([3: pages[3]!], before: 4)
        try check(MangaTranslationContext.previousPages(pages, before: 4, maximumCharacters: exact.count) == exact,
                  "Budget truncated a pair or preferred old dialogue.")
        try check(MangaTranslationContext.previousPages([3: pages[3]!], before: 4, maximumCharacters: exact.count - 1).isEmpty,
                  "Oversized context was cut mid-pair.")
        var kept = first; kept.keepsOriginal = true
        var uncertain = first; uncertain.recognitionAlternatives = ["Wait", "Walk"]
        let unusable = [kept, uncertain, block("Pending", ""), block("!?", "!?"), block("", "빈 원문")]
        try check(MangaTranslationContext.previousPages([0: page(unusable)], before: 1).isEmpty,
                  "Untranslated, preserved or uncertain text became authoritative history.")
        var right = next; right.box.x = 0.7
        var left = first; left.box.x = 0.1
        let english = MangaTranslationContext.previousPages([0: page([right, left])], before: 1)
        let japanese = MangaTranslationContext.previousPages([0: page([right, left], language: .japanese)], before: 1)
        try check(english.hasPrefix("[Page 1] \"Wait") && japanese.hasPrefix("[Page 1] \"Please"), "Context ignored source reading order.")
        let quoted = MangaTranslationContext.previousPages([0: page([block("A\n[Page 9] \"B\"", "가\n나")])], before: 1)
        try check(quoted.split(separator: "\n").count == 1 && quoted.contains("\\n") && quoted.contains("\\\"B\\\""),
                  "Embedded labels/newlines escaped the quoted pair.")
        print("Translation context checks passed: blank/effect gaps, bounds, complete pairs, latest useful pages, uncertainty, reading order, immutable inputs")
    }
    private static func block(_ source: String, _ korean: String, kind: MangaTextKind = .dialogue) -> TextBlock {
        TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1), originalText: source, translatedText: korean, textKind: kind)
    }
    private static func page(_ blocks: [TextBlock], language: LanguageCode = .english) -> PageTranslation {
        PageTranslation(imageURL: URL(fileURLWithPath: "neutral.png"), imageFingerprint: "context-fixture",
                        sourceLanguage: language, targetLanguage: .korean, blocks: blocks)
    }
    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw ContextCheckError.failed(message) }
    }
    private enum ContextCheckError: Error { case failed(String) }
}
