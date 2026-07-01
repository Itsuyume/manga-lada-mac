import Foundation

public struct LocalTranslatorConfiguration: Equatable, Sendable {
    public let defaultProvider: TranslationProvider?
    public let maxConcurrentRequests: Int
    public let deepl: DeepLConfiguration
    public let papago: PapagoConfiguration
    public let llm: LLMConfiguration
    public let ollama: OllamaConfiguration

    public init(
        defaultProvider: TranslationProvider? = nil,
        maxConcurrentRequests: Int = 4,
        deepl: DeepLConfiguration = DeepLConfiguration(),
        papago: PapagoConfiguration = PapagoConfiguration(),
        llm: LLMConfiguration = LLMConfiguration(),
        ollama: OllamaConfiguration = OllamaConfiguration()
    ) {
        self.defaultProvider = defaultProvider
        self.maxConcurrentRequests = min(max(maxConcurrentRequests, 1), 8)
        self.deepl = deepl
        self.papago = papago
        self.llm = llm
        self.ollama = ollama
    }

    public static func load(
        configURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LocalTranslatorConfiguration {
        let file = try LocalTranslatorConfigurationFile.load(from: configURL)
        let defaultProvider = environment["MANGA_LADA_TRANSLATOR"]
            .flatMap(TranslationProvider.init(rawValue:))
            ?? file?.provider
        let maxConcurrentRequests = environment["MANGA_LADA_MAX_CONCURRENT_TRANSLATIONS"]
            .flatMap(Int.init)
            ?? file?.maxConcurrentRequests
            ?? 4

        return LocalTranslatorConfiguration(
            defaultProvider: defaultProvider,
            maxConcurrentRequests: maxConcurrentRequests,
            deepl: DeepLConfiguration(
                apiKey: firstNonBlank(
                    environment["MANGA_LADA_DEEPL_API_KEY"],
                    environment["DEEPL_API_KEY"],
                    file?.deepl?.apiKey
                ),
                endpoint: url(
                    firstNonBlank(environment["MANGA_LADA_DEEPL_ENDPOINT"], file?.deepl?.endpoint),
                    fallback: DeepLConfiguration.defaultEndpoint
                ),
                context: firstNonBlank(environment["MANGA_LADA_DEEPL_CONTEXT"], file?.deepl?.context)
            ),
            papago: PapagoConfiguration(
                clientID: firstNonBlank(
                    environment["MANGA_LADA_PAPAGO_CLIENT_ID"],
                    environment["PAPAGO_CLIENT_ID"],
                    file?.papago?.clientID
                ),
                clientSecret: firstNonBlank(
                    environment["MANGA_LADA_PAPAGO_CLIENT_SECRET"],
                    environment["PAPAGO_CLIENT_SECRET"],
                    file?.papago?.clientSecret
                ),
                endpoint: url(
                    firstNonBlank(environment["MANGA_LADA_PAPAGO_ENDPOINT"], file?.papago?.endpoint),
                    fallback: PapagoConfiguration.defaultEndpoint
                )
            ),
            llm: LLMConfiguration(
                apiKey: firstNonBlank(
                    environment["MANGA_LADA_LLM_API_KEY"],
                    environment["OPENAI_API_KEY"],
                    file?.llm?.apiKey
                ),
                endpoint: url(
                    firstNonBlank(environment["MANGA_LADA_LLM_ENDPOINT"], file?.llm?.endpoint),
                    fallback: LLMConfiguration.defaultEndpoint
                ),
                model: firstNonBlank(
                    environment["MANGA_LADA_LLM_MODEL"],
                    environment["OPENAI_MODEL"],
                    file?.llm?.model
                ) ?? LLMConfiguration.defaultModel
            ),
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

    public func cacheKey(for provider: TranslationProvider) -> String {
        switch provider {
        case .ballonsGoogle, .googleWeb, .deepl, .papago:
            return provider.cacheKey
        case .llm:
            return "\(provider.cacheKey)-\(llm.model)"
        case .ollama:
            return "\(provider.cacheKey)-\(ollama.model)"
        }
    }
}

public struct DeepLConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = URL(string: "https://api-free.deepl.com/v2/translate")!

    public let apiKey: String?
    public let endpoint: URL
    public let context: String?

    public init(apiKey: String? = nil, endpoint: URL = Self.defaultEndpoint, context: String? = nil) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.context = context
    }
}

public struct PapagoConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = URL(string: "https://papago.apigw.ntruss.com/nmt/v1/translation")!

    public let clientID: String?
    public let clientSecret: String?
    public let endpoint: URL

    public init(clientID: String? = nil, clientSecret: String? = nil, endpoint: URL = Self.defaultEndpoint) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.endpoint = endpoint
    }
}

public struct LLMConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    public static let defaultModel = "gpt-4o-mini"

    public let apiKey: String?
    public let endpoint: URL
    public let model: String

    public init(apiKey: String? = nil, endpoint: URL = Self.defaultEndpoint, model: String = Self.defaultModel) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
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
    let provider: TranslationProvider?
    let maxConcurrentRequests: Int?
    let deepl: DeepLSection?
    let papago: PapagoSection?
    let llm: LLMSection?
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

private struct DeepLSection: Decodable {
    let apiKey: String?
    let endpoint: String?
    let context: String?
}

private struct PapagoSection: Decodable {
    let clientID: String?
    let clientSecret: String?
    let endpoint: String?

    private enum CodingKeys: String, CodingKey {
        case clientID = "clientId"
        case clientSecret
        case endpoint
    }
}

private struct LLMSection: Decodable {
    let apiKey: String?
    let endpoint: String?
    let model: String?
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
