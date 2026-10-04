import Foundation

/// One catalog supplies OCR kind hints and conservative preferred Korean forms.
/// Entries without a Korean form intentionally defer to context-dependent translation.
public struct JapaneseSoundEffectLexicon: Sendable {
    public let sourceForms: [String]
    public let recognitionPatterns: [String]
    private let translations: [String: String]
    private let meanings: [String: String]
    private let recognizedSources: Set<String>

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
    }

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "sound-effect-lexicon", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Self(data: Data(contentsOf: url))
    }
    public func translation(for source: String) -> String? { translations[Self.normalized(source)] }
    public func meaning(for source: String) -> String? { meanings[Self.normalized(source)] }
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
        text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.!?。…・"))
    }
    private struct Catalog: Decodable { let version: Int; let entries: [Entry]; let recognitionPatterns: [String]? }
    private struct Entry: Decodable {
        let sources: [String]; let korean: String?; let meaning: String?; let recognition: Bool?
    }
    private enum LexiconError: LocalizedError {
        case invalidCatalog
        var errorDescription: String? { "효과음 사전의 버전·원문·한국어 표기가 올바르지 않거나 중복되었습니다." }
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
