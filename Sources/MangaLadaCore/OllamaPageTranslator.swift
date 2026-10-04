import Foundation

// Reuses the earlier Ollama /api/chat boundary with a strict page response contract.
public struct OllamaPageTranslator: MangaPageTranslating {
    private let configuration: OllamaConfiguration
    private let session: URLSession
    private let selectedIDs: Set<UUID>?
    public init(configuration: OllamaConfiguration = OllamaConfiguration(), session: URLSession = .shared, selectedIDs: Set<UUID>? = nil) {
        self.configuration = configuration
        self.session = session
        self.selectedIDs = selectedIDs
    }

    public func translatePage(_ blocks: [TextBlock], previousContext: String = "") async throws -> [TextBlock] {
        guard !blocks.isEmpty else { return [] }
        if configuration.isTranslationSpecialist {
            return try await TranslateGemmaPageTranslator(configuration: configuration, session: session, selectedIDs: selectedIDs)
                .translatePage(blocks, previousContext: previousContext)
        }
        return try await OllamaChatClient(configuration: configuration, session: session).validated(
            system: MangaTranslationPrompt.system, user: MangaTranslationPrompt.user(blocks: blocks, previousContext: previousContext),
            schema: .page(count: blocks.count), outputTokens: blocks.count * 160) { try MangaPageResponse.decode($0, blocks: blocks, selectedIDs: selectedIDs) }
    }
}

enum TranslationHTTP {
    static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw TranslationError.httpStatus(http.statusCode) }
        return data
    }
}
