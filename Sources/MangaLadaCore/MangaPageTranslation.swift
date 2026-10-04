import Foundation

public enum MangaTextKind: String, Codable, CaseIterable, Sendable {
    case dialogue
    case caption
    case title
    case soundEffect
}

public protocol MangaPageTranslating: Sendable {
    func translatePage(_ blocks: [TextBlock], previousContext: String) async throws -> [TextBlock]
}

public enum MangaReadingOrder {
    public static func sorted(_ blocks: [TextBlock]) -> [TextBlock] {
        // Fixed row bands keep the comparator transitive; within a row read right to left.
        blocks.sorted { lhs, rhs in
            let leftRow = Int((lhs.box.y / 0.12).rounded(.down))
            let rightRow = Int((rhs.box.y / 0.12).rounded(.down))
            if leftRow != rightRow { return leftRow < rightRow }
            if lhs.box.x != rhs.box.x { return lhs.box.x > rhs.box.x }
            return lhs.box.y < rhs.box.y
        }
    }
}

public enum MangaPageResponse {
    public static func decode(_ data: Data, blocks: [TextBlock], selectedIDs: Set<UUID>? = nil) throws -> [TextBlock] {
        if let selectedIDs, !selectedIDs.isSubset(of: Set(blocks.map(\.id))) {
            throw TranslationError.invalidPageResponse("선택한 영역이 현재 페이지에 없습니다.")
        }
        let response: PageResponse
        do { response = try JSONDecoder().decode(PageResponse.self, from: data) }
        catch DecodingError.keyNotFound(let key, let context) {
            let path = (context.codingPath + [key]).reduce("") { path, component in
                if let index = component.intValue { return "\(path)[\(index)]" }
                return path.isEmpty ? component.stringValue : "\(path).\(component.stringValue)"
            }
            throw TranslationError.invalidPageResponse("모델 응답에서 필수 항목이 빠졌습니다: \(path)")
        }
        catch { throw TranslationError.invalidPageResponse("JSON 형식 오류: \(error.localizedDescription)") }
        guard response.translations.count == blocks.count else {
            throw TranslationError.invalidPageResponse("\(blocks.count)개 영역 중 \(response.translations.count)개만 반환되었습니다.")
        }
        let ids = response.translations.map(\.id)
        guard Set(ids) == Set(blocks.indices), Set(ids).count == ids.count else {
            throw TranslationError.invalidPageResponse("영역 번호 누락 또는 중복")
        }
        let entries = Dictionary(uniqueKeysWithValues: response.translations.map { ($0.id, $0) })
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        return try blocks.enumerated().map { index, block in
            // Context output is discarded. Its language cannot invalidate an unrelated selection.
            if let selectedIDs, !selectedIDs.contains(block.id) { return block }
            guard let entry = entries[index] else {
                throw TranslationError.invalidPageResponse("영역 \(index) 누락")
            }
            let text = try MaskedTextTranslation.validated(entry.text.trimmingCharacters(in: .whitespacesAndNewlines), source: block.originalText)
            let hasKorean = TextLanguageDetector.containsKorean(text)
            let sourceHasJapanese = TextLanguageDetector.containsJapanese(block.originalText)
            let nonverbal = TextLanguageDetector.isNonverbalTranslation(text, source: block.originalText)
            guard !text.isEmpty, (!sourceHasJapanese || nonverbal || hasKorean), text.range(of: #"[\p{Hiragana}\p{Katakana}\p{Han}]"#, options: .regularExpression) == nil else {
                throw TranslationError.invalidPageResponse("영역 \(index)에 한국어 번역이 없습니다. 원문: \(block.originalText) / 모델 응답: \(text)")
            }
            var translated = block
            translated.textKind = block.textKind ?? entry.kind
            translated.translatedText = translated.textKind == .soundEffect
                ? try SoundEffectTranslation.text(text, source: block.originalText, lexicon: lexicon) : text
            return translated
        }
    }

    private struct PageResponse: Decodable { let translations: [Entry] }
    private struct Entry: Decodable {
        let id: Int
        let text: String
        let kind: MangaTextKind
    }
}

enum MangaTranslationPrompt {
    static let system = """
    You are a professional Japanese-to-Korean manga translator. Translate ALL numbered regions together using page context and Japanese right-to-left reading order. Preserve names, relationships, tense, speaker tone, honorifics, jokes and sentence meaning. Use fluent Korean and translate all written content while preserving intentional omissions. Never invent missing plot facts. Previous-page text is context only, not new regions to translate.
    Classify each region as dialogue, caption, or soundEffect. Render Japanese onomatopoeia by meaning as concise natural Korean sound effects (ドーン -> 쾅, ゴゴゴ -> 고오오, ドキドキ -> 두근두근, サラサラ -> 사락사락 or 찰랑찰랑 depending on the scene). Never just transliterate a Japanese sound into Hangul (e.g. サラサラ is not 살라살라). Short speech is still dialogue when it is spoken. Use Korean script, punctuation and needed numbers. Do not output Japanese, explanations, romaji or markdown. Keep dialogue compact without summarizing away meaning. Return JSON {"translations":[{"id":0,"text":"한국어","kind":"dialogue"}]} with each input id exactly once.
    """

    static func user(blocks: [TextBlock], previousContext: String) throws -> String {
        let regions = blocks.enumerated().map { index, block in
            Region(id: index, text: MaskedTextTranslation.modelText(block.originalText), x: block.box.x, y: block.box.y,
                   width: block.box.width, height: block.box.height, vertical: block.sourceIsVertical == true, detectedKind: block.textKind)
        }
        let data = try JSONEncoder().encode(regions)
        let masking = MaskedTextTranslation.instruction(for: blocks.map(\.originalText))
        return "Previous page (context only):\n\(previousContext.suffix(3_000))\n\(masking)\nRegions in reading order:\n\(String(decoding: data, as: UTF8.self))"
    }

    private struct Region: Encodable {
        let id: Int
        let text: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let vertical: Bool
        let detectedKind: MangaTextKind?
    }
}
