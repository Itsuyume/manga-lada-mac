import Foundation

/// Shared, bounded history for page, selection and manual-region translation.
public enum MangaTranslationContext {
    public static func previousPages(_ pages: [Int: PageTranslation], before index: Int,
                                     maximumCharacters: Int = 3_000, maximumPages: Int = 3) -> String {
        guard index > 0, maximumCharacters > 0, maximumPages > 0 else { return "" }
        var entries: [String] = [], characters = 0, usefulPages = 0
        let indices = pages.keys.filter { $0 >= 0 && $0 < index }.sorted(by: >)
        for pageIndex in indices {
            guard let page = pages[pageIndex] else { continue }
            let before = entries.count
            let blocks = MangaReadingOrder.sorted(page.blocks.filter(isUseful), sourceLanguage: page.sourceLanguage)
            for block in blocks.reversed() {
                let source = block.originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                let korean = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
                // Quoted data keeps embedded newlines and labels inside the source/translation pair.
                let entry = "[Page \(pageIndex + 1)] \(String(reflecting: source)) -> \(String(reflecting: korean))"
                let cost = entry.count + (entries.isEmpty ? 0 : 1)
                guard cost <= maximumCharacters - characters else { continue }
                entries.append(entry); characters += cost
            }
            if entries.count > before { usefulPages += 1 }
            if usefulPages == maximumPages { break }
        }
        return entries.reversed().joined(separator: "\n")
    }

    private static func isUseful(_ block: TextBlock) -> Bool {
        !block.preservesOriginalArtwork && block.textKind != .soundEffect
            && !block.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !TextLanguageDetector.isPunctuationOnly(block.originalText)
            && MaskedTextTranslation.reviewMessage(for: block) == nil
    }
}
