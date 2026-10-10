import Foundation

public struct TranslateGemmaPageTranslator: MangaPageTranslating {
    private let configuration: OllamaConfiguration
    private let session: URLSession
    private let selectedIDs: Set<UUID>?
    private let sourceLanguage: LanguageCode
    public init(configuration: OllamaConfiguration = OllamaConfiguration(), session: URLSession = .shared, selectedIDs: Set<UUID>? = nil,
                sourceLanguage: LanguageCode = .japanese) {
        self.configuration = configuration; self.session = session; self.selectedIDs = selectedIDs
        self.sourceLanguage = sourceLanguage
    }
    public func translatePage(_ blocks: [TextBlock], previousContext: String = "") async throws -> [TextBlock] {
        guard !blocks.isEmpty else { return [] }
        let numbered = blocks.enumerated().map {
            let text = sourceLanguage == .japanese ? MaskedTextTranslation.modelText($0.element.originalText) : $0.element.originalText
            return "[R\($0.offset)] \(text.replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")
        let masking = sourceLanguage == .japanese ? MaskedTextTranslation.instruction(for: blocks.map(\.originalText)) : ""
        let effects = sourceLanguage == .japanese ? try MangaTranslationPrompt.soundEffectGuidance(blocks: blocks)
            : "Translate comic effects by their sound/motion as natural Korean onomatopoeia; preserve repetition."
        let context = "Previous page (context only, do not translate):\n" + previousContext.suffix(3_000)
        let prompt = """
        You are a professional \(sourceLanguage.displayName) (\(sourceLanguage.rawValue)) to Korean (ko) translator. Accurately convey the meaning and nuances of the original text in natural Korean.
        Produce only the Korean translation, without any additional explanations or commentary. Preserve every [R0], [R1] identifier exactly, with one translated region per identifier. These manga regions include dialogue, narration and sound effects. Preserve speaker tone and render all names and honorifics in Korean script.
        \(masking)
        \(MangaTranslationPrompt.dialogueGuidance(blocks: blocks, sourceLanguage: sourceLanguage))
        \(context)
        \(effects)
        Please translate the following \(sourceLanguage.displayName) text into Korean:

        \(numbered)
        """
        let client = OllamaChatClient(configuration: configuration, session: session)
        var instruction = prompt
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let outputTokens = max(1024, blocks.reduce(0) { $0 + $1.originalText.count * 3 + 96 })
            let response = try await client.text(user: instruction, outputTokens: outputTokens)
            do { return try MangaNumberedPageResponse.decode(response, blocks: blocks, selectedIDs: selectedIDs) }
            catch TranslationError.invalidPageResponse(let detail) {
                guard attempt == 0 else { throw TranslationError.invalidPageResponse(detail) }
                instruction = """
                You are a professional \(sourceLanguage.displayName) (\(sourceLanguage.rawValue)) to Korean (ko) translator. Output only Korean text after every numbered [R0], [R1] marker. Never repeat the original, including inside quotations or parentheses. Render every name in Korean script. Translate each numbered region exactly once.
                \(masking)
                \(MangaTranslationPrompt.dialogueGuidance(blocks: blocks, sourceLanguage: sourceLanguage))
                \(context)
                \(effects)
                The previous response failed validation: \(detail)
                Please translate the following \(sourceLanguage.displayName) text into Korean:

                \(numbered)
                """
            }
        }
        throw TranslationError.invalidResponse
    }
}

public enum MangaNumberedPageResponse {
    public static func decode(_ text: String, blocks: [TextBlock], selectedIDs: Set<UUID>? = nil) throws -> [TextBlock] {
        let expression = try NSRegularExpression(pattern: #"\[R(\d+)\]\s*([\s\S]*?)(?=\[R\d+\]|\z)"#)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: range)
        guard let first = matches.first, first.range.location == 0 || text.prefix(first.range.location).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.invalidPageResponse("번역 모델이 영역 번호 없이 응답했습니다.")
        }
        let entries = try matches.map { match -> Entry in
            guard let idRange = Range(match.range(at: 1), in: text), let textRange = Range(match.range(at: 2), in: text),
                  let id = Int(text[idRange]), blocks.indices.contains(id) else {
                throw TranslationError.invalidPageResponse("번역 모델이 잘못된 영역 번호를 반환했습니다.")
            }
            return Entry(id: id, text: String(text[textRange]), kind: blocks[id].textKind ?? .dialogue)
        }
        return try MangaPageResponse.decode(JSONEncoder().encode(Response(translations: entries)), blocks: blocks, selectedIDs: selectedIDs)
    }
    private struct Entry: Encodable { let id: Int; let text: String; let kind: MangaTextKind }
    private struct Response: Encodable { let translations: [Entry] }
}
