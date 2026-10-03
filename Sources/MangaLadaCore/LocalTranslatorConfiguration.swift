import Foundation

public struct LocalTranslatorConfiguration: Equatable, Sendable {
    public var provider: TranslationProvider
    public let maxConcurrentRequests: Int
    public var ollama: OllamaConfiguration
    public var gemini: GeminiConfiguration
    public var enhanceSoundEffects: Bool

    public init(provider: TranslationProvider = .ollama, maxConcurrentRequests: Int = 1,
                ollama: OllamaConfiguration = OllamaConfiguration(), gemini: GeminiConfiguration = GeminiConfiguration(), enhanceSoundEffects: Bool = false) {
        self.provider = provider
        self.maxConcurrentRequests = min(max(maxConcurrentRequests, 1), 8)
        self.ollama = ollama
        self.gemini = gemini
        self.enhanceSoundEffects = enhanceSoundEffects
    }

    public static func load(configURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        let file: ConfigurationFile?
        if FileManager.default.fileExists(atPath: configURL.path) {
            file = try JSONDecoder().decode(ConfigurationFile.self, from: Data(contentsOf: configURL))
        } else { file = nil }
        return Self(
            provider: file?.provider ?? .ollama,
            maxConcurrentRequests: environment["MANGA_LADA_MAX_CONCURRENT_TRANSLATIONS"].flatMap(Int.init) ?? file?.maxConcurrentRequests ?? 1,
            ollama: OllamaConfiguration(model: environment["MANGA_LADA_OLLAMA_MODEL"] ?? file?.ollamaModel ?? OllamaConfiguration.defaultModel),
            gemini: GeminiConfiguration(model: file?.geminiModel ?? GeminiConfiguration.defaultModel, apiKey: environment["GEMINI_API_KEY"] ?? ""),
            enhanceSoundEffects: file?.enhanceSoundEffects ?? false
        )
    }

    public func save(to url: URL) throws {
        let file = ConfigurationFile(provider: provider, maxConcurrentRequests: maxConcurrentRequests,
                                     ollamaModel: ollama.model, geminiModel: gemini.model, enhanceSoundEffects: enhanceSoundEffects)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    public var cacheKey: String {
        let model = provider == .ollama ? ollama.model : gemini.model
        return provider == .googleWeb ? provider.cacheKey : "\(provider.cacheKey)-\(model.replacingOccurrences(of: "/", with: "-"))-page-v1"
    }

    public var usesPreviousPageContext: Bool {
        provider == .geminiFlashLite || (provider == .ollama && !ollama.isTranslationSpecialist)
    }

    private struct ConfigurationFile: Codable {
        let provider: TranslationProvider?
        let maxConcurrentRequests: Int?
        let ollamaModel: String?
        let geminiModel: String?
        let enhanceSoundEffects: Bool?
    }
}

public struct OllamaConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    public static let defaultModel = "translategemma:12b"
    public static let visionModel = "qwen3.5:9b"
    public let endpoint: URL
    public var model: String
    public var isTranslationSpecialist: Bool { model.lowercased().hasPrefix("translategemma") }
    public init(endpoint: URL = Self.defaultEndpoint, model: String = Self.defaultModel) {
        self.endpoint = endpoint
        self.model = model
    }
}

public struct GeminiConfiguration: Equatable, Sendable {
    public static let defaultModel = "gemini-2.5-flash-lite"
    public var model: String
    public var apiKey: String
    public init(model: String = Self.defaultModel, apiKey: String = "") {
        self.model = model
        self.apiKey = apiKey
    }
}
