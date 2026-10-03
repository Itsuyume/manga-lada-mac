import Foundation

/// One catalog supplies OCR kind hints and conservative preferred Korean forms.
/// Entries without a Korean form intentionally defer to context-dependent translation.
public struct JapaneseSoundEffectLexicon: Sendable {
    public let sourceForms: [String]
    public let recognitionPatterns: [String]
    private let translations: [String: String]

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.version == 1, !catalog.entries.isEmpty else { throw LexiconError.invalidCatalog }
        recognitionPatterns = catalog.recognitionPatterns ?? []
        for pattern in recognitionPatterns {
            guard !pattern.isEmpty else { throw LexiconError.invalidCatalog }
            _ = try NSRegularExpression(pattern: pattern)
        }
        var sources = Set<String>(), preferred: [String: String] = [:]
        for entry in catalog.entries {
            guard !entry.sources.isEmpty else { throw LexiconError.invalidCatalog }
            if let korean = entry.korean {
                guard TextLanguageDetector.containsKorean(korean), !TextLanguageDetector.containsJapanese(korean),
                      korean == korean.trimmingCharacters(in: .whitespacesAndNewlines) else { throw LexiconError.invalidCatalog }
            }
            for source in entry.sources {
                let normalized = Self.normalized(source)
                guard !normalized.isEmpty, TextLanguageDetector.containsJapanese(normalized), sources.insert(normalized).inserted else {
                    throw LexiconError.invalidCatalog
                }
                preferred[normalized] = entry.korean
            }
        }
        sourceForms = sources.sorted()
        translations = preferred
    }

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "sound-effect-lexicon", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Self(data: Data(contentsOf: url))
    }
    public func translation(for source: String) -> String? { translations[Self.normalized(source)] }
    private static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n.!?。…・"))
    }
    private struct Catalog: Decodable { let version: Int; let entries: [Entry]; let recognitionPatterns: [String]? }
    private struct Entry: Decodable { let sources: [String]; let korean: String? }
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
        guard TextLanguageDetector.containsKorean(text) else {
            throw TranslationError.invalidPageResponse("효과음 번역에 설명만 있거나 한국어 효과음이 없습니다: \(source)")
        }
        return lexicon.translation(for: source) ?? text
    }
}
