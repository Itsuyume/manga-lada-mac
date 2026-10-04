import Foundation

public struct TranslateGemmaPageTranslator: MangaPageTranslating {
    private let configuration: OllamaConfiguration
    private let session: URLSession
    private let selectedIDs: Set<UUID>?
    public init(configuration: OllamaConfiguration = OllamaConfiguration(), session: URLSession = .shared, selectedIDs: Set<UUID>? = nil) {
        self.configuration = configuration; self.session = session; self.selectedIDs = selectedIDs
    }
    public func translatePage(_ blocks: [TextBlock], previousContext: String = "") async throws -> [TextBlock] {
        guard !blocks.isEmpty else { return [] }
        let numbered = blocks.enumerated().map { "[R\($0.offset)] \($0.element.originalText.replacingOccurrences(of: "\n", with: " "))" }.joined(separator: "\n")
        let prompt = """
        You are a professional Japanese (ja) to Korean (ko) translator. Your goal is to accurately convey the meaning and nuances of the original Japanese text while adhering to Korean grammar, vocabulary, and cultural sensitivities.
        Produce only the Korean translation, without any additional explanations or commentary. Preserve every [R0], [R1] identifier exactly, with one translated region per identifier. These are manga dialogues: preserve speaker tone and render all names and honorifics in Korean script. Please translate the following Japanese text into Korean:


        \(numbered)
        """
        let client = OllamaChatClient(configuration: configuration, session: session)
        var instruction = prompt
        for attempt in 0..<2 {
            try Task.checkCancellation()
            let response = try await client.text(user: instruction, outputTokens: blocks.count * 100)
            do { return try MangaNumberedPageResponse.decode(response, blocks: blocks, selectedIDs: selectedIDs) }
            catch TranslationError.invalidPageResponse(let detail) {
                guard attempt == 0 else { throw TranslationError.invalidPageResponse(detail) }
                instruction = """
                You are a professional Japanese (ja) to Korean (ko) translator. Output only Korean text after every numbered [R0], [R1] marker. Never repeat the Japanese original, including inside quotations or parentheses. Render every name and honorific in Korean script. Translate each numbered region exactly once. Please translate the following Japanese text into Korean:


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
