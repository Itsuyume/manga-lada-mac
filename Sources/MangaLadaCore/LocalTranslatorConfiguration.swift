import Foundation

public struct LocalTranslatorConfiguration: Equatable, Sendable {
    public let maxConcurrentRequests: Int
    public let ollama: OllamaConfiguration

    public init(
        maxConcurrentRequests: Int = 4,
        ollama: OllamaConfiguration = OllamaConfiguration()
    ) {
        self.maxConcurrentRequests = min(max(maxConcurrentRequests, 1), 8)
        self.ollama = ollama
    }

    public static func load(
        configURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LocalTranslatorConfiguration {
        let file = try LocalTranslatorConfigurationFile.load(from: configURL)
        let maxConcurrentRequests = environment["MANGA_LADA_MAX_CONCURRENT_TRANSLATIONS"]
            .flatMap(Int.init)
            ?? file?.maxConcurrentRequests
            ?? 4

        return LocalTranslatorConfiguration(
            maxConcurrentRequests: maxConcurrentRequests,
            ollama: OllamaConfiguration(
                endpoint: url(
                    firstNonBlank(environment["MANGA_LADA_OLLAMA_ENDPOINT"], file?.ollama?.endpoint),
                    fallback: OllamaConfiguration.defaultEndpoint
                ),
                model: firstNonBlank(
                    environment["MANGA_LADA_OLLAMA_MODEL"],
                    file?.ollama?.model
                ) ?? OllamaConfiguration.defaultModel
            )
        )
    }

    public var cacheKey: String {
        "\(TranslationProvider.ollama.cacheKey)-\(ollama.model)"
    }
}

public struct OllamaConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    public static let defaultModel = "gemma3:4b"

    public let endpoint: URL
    public let model: String

    public init(endpoint: URL = Self.defaultEndpoint, model: String = Self.defaultModel) {
        self.endpoint = endpoint
        self.model = model
    }
}

private struct LocalTranslatorConfigurationFile: Decodable {
    let maxConcurrentRequests: Int?
    let ollama: OllamaSection?

    static func load(from url: URL) throws -> LocalTranslatorConfigurationFile? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(LocalTranslatorConfigurationFile.self, from: Data(contentsOf: url))
        } catch {
            throw TranslationError.missingConfiguration(
                "번역기 로컬 설정 파일을 읽지 못했습니다: \(url.path)"
            )
        }
    }
}

private struct OllamaSection: Decodable {
    let endpoint: String?
    let model: String?
}

private func firstNonBlank(_ values: String?...) -> String? {
    values.lazy.compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }.first
}

private func url(_ value: String?, fallback: URL) -> URL {
    guard let value, let url = URL(string: value) else {
        return fallback
    }
    return url
}
