import Foundation

/// One catalog supplies OCR kind hints and conservative preferred Korean forms.
/// Entries without a Korean form intentionally defer to context-dependent translation.
public struct JapaneseSoundEffectLexicon: Sendable {
    public let sourceForms: [String]
    public let recognitionPatterns: [String]
    private let translations: [String: String]
    private let meanings: [String: String]
    private let recognizedSources: Set<String>
    private let reviewChoices: [String: [ReviewOption]]

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.version == 1, !catalog.entries.isEmpty else { throw LexiconError.invalidCatalog }
        recognitionPatterns = catalog.recognitionPatterns ?? []
        for pattern in recognitionPatterns {
            guard !pattern.isEmpty else { throw LexiconError.invalidCatalog }
            _ = try NSRegularExpression(pattern: pattern)
        }
        var sources = Set<String>(), automatic = Set<String>(), preferred: [String: String] = [:], hints: [String: String] = [:]
        for entry in catalog.entries {
            guard !entry.sources.isEmpty else { throw LexiconError.invalidCatalog }
            if let korean = entry.korean {
                guard TextLanguageDetector.containsKorean(korean), !TextLanguageDetector.containsJapanese(korean),
                      korean == korean.trimmingCharacters(in: .whitespacesAndNewlines) else { throw LexiconError.invalidCatalog }
            }
            if let meaning = entry.meaning {
                guard !meaning.isEmpty, meaning.count <= 600,
                      meaning == meaning.trimmingCharacters(in: .whitespacesAndNewlines) else { throw LexiconError.invalidCatalog }
            }
            for source in entry.sources {
                let normalized = Self.normalized(source)
                guard !normalized.isEmpty, TextLanguageDetector.containsJapanese(normalized), sources.insert(normalized).inserted else {
                    throw LexiconError.invalidCatalog
                }
                preferred[normalized] = entry.korean
                hints[normalized] = entry.meaning
                if entry.recognition != false { automatic.insert(normalized) }
            }
        }
        sourceForms = automatic.sorted()
        recognizedSources = automatic
        translations = preferred
        meanings = hints
        reviewChoices = try Self.decodeReviewChoices(catalog.reviewGroups ?? [], sources: sources)
    }

    private static func decodeReviewChoices(_ groups: [ReviewGroup], sources: Set<String>) throws -> [String: [ReviewOption]] {
        var choices: [String: [ReviewOption]] = [:]
        for group in groups {
            guard !group.sources.isEmpty, (2...8).contains(group.options.count),
                  group.options.allSatisfy(\.isValid), Set(group.options).count == group.options.count else {
                throw LexiconError.invalidCatalog
            }
            for source in group.sources {
                let key = Self.normalized(source)
                guard sources.contains(key), choices[key] == nil else { throw LexiconError.invalidCatalog }
                choices[key] = group.options
            }
        }
        return choices
    }

    public static func bundled() throws -> Self {
        let resources = try PackageResourceBundle.load(named: "MangaLadaMac_MangaLadaCore") { Bundle.module }
        guard let url = resources.url(forResource: "sound-effect-lexicon", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Self(data: Data(contentsOf: url))
    }
    public func translation(for source: String) -> String? { translations[Self.normalized(source)] }
    public func meaning(for source: String) -> String? {
        let text = Self.normalized(source)
        if let meaning = meanings[text] { return meaning }
        guard let repetition = repeatedEntry(for: text), let meaning = meanings[repetition.source] else { return nil }
        return "Repeat \(repetition.source) \(repetition.count) times: \(meaning)"
    }
    /// Contextual candidates never force a fixed translation or change classification.
    public func reviewOptions(for source: String) -> [ReviewOption] {
        let text = Self.normalized(source)
        if let choices = reviewChoices[text] { return choices }
        guard let repetition = repeatedEntry(for: text) else { return [] }
        return (reviewChoices[repetition.source] ?? []).map {
            ReviewOption(context: $0.context, korean: String(repeating: $0.korean, count: repetition.count))
        }
    }
    private func repeatedEntry(for text: String) -> (source: String, count: Int)? {
        let characters = Array(text)
        for count in 2...4 where !characters.isEmpty && characters.count.isMultiple(of: count) {
            let unit = String(characters.prefix(characters.count / count))
            if recognizedSources.contains(unit), String(repeating: unit, count: count) == text {
                return (unit, count)
            }
        }
        return nil
    }
    public func inferKinds(_ blocks: [TextBlock], selectedIDs: Set<UUID>? = nil) -> [TextBlock] {
        blocks.map { block in
            guard selectedIDs?.contains(block.id) != false, block.balloonShape == nil,
                  block.userDefinedTextKind != true, block.userDefinedBounds == nil,
                  block.textKind != .title, recognizes(block.originalText) else { return block }
            var effect = block; effect.textKind = .soundEffect
            return effect
        }
    }
    public func recognizes(_ source: String) -> Bool {
        let text = Self.normalized(source)
        return recognizedSources.contains(text) || recognitionPatterns.contains { pattern in
            guard let range = text.range(of: pattern, options: .regularExpression) else { return false }
            return range == text.startIndex..<text.endIndex
        }
    }
    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.filter { !$0.isWhitespace }
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?。…・"))
    }
    public struct ReviewOption: Decodable, Hashable, Sendable {
        public let context: String
        public let korean: String
        fileprivate var isValid: Bool {
            [context, korean].allSatisfy {
                !$0.isEmpty && $0.count <= 40 && !$0.contains(where: \.isNewline)
                    && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    && TextLanguageDetector.containsKorean($0) && !TextLanguageDetector.containsJapanese($0)
            }
        }
    }
    private struct Catalog: Decodable {
        let version: Int; let entries: [Entry]; let recognitionPatterns: [String]?; let reviewGroups: [ReviewGroup]?
    }
    private struct ReviewGroup: Decodable { let sources: [String]; let options: [ReviewOption] }
    private struct Entry: Decodable {
        let sources: [String]; let korean: String?; let meaning: String?; let recognition: Bool?
    }
    private enum LexiconError: LocalizedError {
        case invalidCatalog
        var errorDescription: String? { "효과음 사전의 버전·원문·한국어 표기·검수 후보가 올바르지 않거나 중복되었습니다." }
    }
}

enum SoundEffectTranslation {
    static func text(_ modelText: String, source: String, lexicon: JapaneseSoundEffectLexicon) throws -> String {
        var text = modelText
        let label = #"^\([^()\n]{0,40}(?:소리|효과음|의성어|의태어)\)\s*"#
        if let range = text.range(of: label, options: .regularExpression) { text.removeSubrange(range) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (opening, closing) in [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")] where text.hasPrefix(opening) && text.hasSuffix(closing) && text.count >= 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard TextLanguageDetector.containsKorean(text) || TextLanguageDetector.isNonverbalTranslation(text, source: source) else {
            throw TranslationError.invalidPageResponse("효과음 번역에 설명만 있거나 한국어 효과음이 없습니다: \(source)")
        }
        return lexicon.translation(for: source) ?? text
    }
}
