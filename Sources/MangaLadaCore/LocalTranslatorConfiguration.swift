import Foundation

public struct LocalTranslatorConfiguration: Equatable, Sendable {
    public var provider: TranslationProvider
    public let maxConcurrentRequests: Int
    public var ollama: OllamaConfiguration
    public var gemini: GeminiConfiguration
    public var enhanceSoundEffects: Bool
    public var interpretMaskedText: Bool
    public var japaneseOCR: JapaneseOCRBackend
    /// The concrete language of the page being processed. In automatic mode the processor
    /// resolves it per page; elsewhere it equals the fixed mode.
    public var sourceLanguage: LanguageCode
    public var sourceLanguageMode: SourceLanguageMode

    /// `sourceLanguageMode` nil keeps a programmatic caller's explicit `sourceLanguage` fixed.
    public init(provider: TranslationProvider = .ollama, maxConcurrentRequests: Int = 1,
                ollama: OllamaConfiguration = OllamaConfiguration(), gemini: GeminiConfiguration = GeminiConfiguration(),
                enhanceSoundEffects: Bool = false, interpretMaskedText: Bool = false,
                japaneseOCR: JapaneseOCRBackend = .manga, sourceLanguage: LanguageCode = .japanese,
                sourceLanguageMode: SourceLanguageMode? = nil) {
        self.provider = provider
        self.maxConcurrentRequests = min(max(maxConcurrentRequests, 1), 8)
        self.ollama = ollama
        self.gemini = gemini
        self.enhanceSoundEffects = enhanceSoundEffects
        self.interpretMaskedText = interpretMaskedText
        self.japaneseOCR = japaneseOCR
        self.sourceLanguageMode = sourceLanguageMode ?? SourceLanguageMode(fixed: sourceLanguage)
        self.sourceLanguage = self.sourceLanguageMode.fixedLanguage ?? sourceLanguage
    }

    public static func load(configURL: URL, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        let file: ConfigurationFile?
        if FileManager.default.fileExists(atPath: configURL.path) {
            file = try JSONDecoder().decode(ConfigurationFile.self, from: Data(contentsOf: configURL))
        } else { file = nil }
        try (file?.sourceLanguage ?? .japanese).validateComicSource()
        // 0.2.48 stored only a fixed language: an explicit English choice stays English,
        // the old Japanese default becomes automatic detection.
        let mode = file?.sourceLanguageMode ?? (file?.sourceLanguage == .english ? .english : .automatic)
        return Self(
            provider: file?.provider ?? .ollama,
            maxConcurrentRequests: environment["MANGA_LADA_MAX_CONCURRENT_TRANSLATIONS"].flatMap(Int.init) ?? file?.maxConcurrentRequests ?? 1,
            ollama: OllamaConfiguration(model: environment["MANGA_LADA_OLLAMA_MODEL"] ?? file?.ollamaModel ?? OllamaConfiguration.defaultModel,
                                       retention: file?.ollamaKeepAlive ?? .balanced),
            gemini: GeminiConfiguration(model: file?.geminiModel ?? GeminiConfiguration.defaultModel, apiKey: environment["GEMINI_API_KEY"] ?? ""),
            enhanceSoundEffects: file?.enhanceSoundEffects ?? false,
            interpretMaskedText: file?.interpretMaskedText ?? true,
            japaneseOCR: file?.japaneseOCR ?? .manga,
            sourceLanguage: mode.fixedLanguage ?? .japanese,
            sourceLanguageMode: mode
        )
    }

    public func save(to url: URL) throws {
        try sourceLanguage.validateComicSource()
        let file = ConfigurationFile(provider: provider, maxConcurrentRequests: maxConcurrentRequests,
                                     ollamaModel: ollama.model, geminiModel: gemini.model, enhanceSoundEffects: enhanceSoundEffects,
                                     ollamaKeepAlive: ollama.retention, interpretMaskedText: interpretMaskedText,
                                     japaneseOCR: japaneseOCR, sourceLanguage: sourceLanguageMode.fixedLanguage ?? .japanese,
                                     sourceLanguageMode: sourceLanguageMode)
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
        provider == .geminiFlashLite || (provider == .ollama && (sourceLanguage == .english || !ollama.isTranslationSpecialist))
    }

    public func requiresRetranslation(comparedTo previous: Self) -> Bool {
        var comparable = self
        // These request policies apply next time; changing them must not discard saved reviews.
        comparable.ollama.retention = previous.ollama.retention
        comparable.interpretMaskedText = previous.interpretMaskedText
        comparable.japaneseOCR = previous.japaneseOCR
        // The concrete language is resolved per page; only the chosen mode is a setting. Entering or
        // leaving automatic mode keeps each processed page in the language it was cached with, so
        // only a switch between two fixed languages discards the current results.
        comparable.sourceLanguage = previous.sourceLanguage
        if comparable.sourceLanguageMode == .automatic || previous.sourceLanguageMode == .automatic {
            comparable.sourceLanguageMode = previous.sourceLanguageMode
        }
        return comparable != previous
    }

    private struct ConfigurationFile: Codable {
        let provider: TranslationProvider?
        let maxConcurrentRequests: Int?
        let ollamaModel: String?
        let geminiModel: String?
        let enhanceSoundEffects: Bool?
        let ollamaKeepAlive: OllamaConfiguration.Retention?
        let interpretMaskedText: Bool?
        let japaneseOCR: JapaneseOCRBackend?
        let sourceLanguage: LanguageCode?
        let sourceLanguageMode: SourceLanguageMode?
    }
}

public struct OllamaConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = URL(string: "http://127.0.0.1:11434/api/chat")!
    public static let defaultModel = "translategemma:12b"
    public static let visionModel = "qwen3.5:9b"
    public let endpoint: URL
    public var model: String
    public var retention: Retention
    public var isTranslationSpecialist: Bool { model.lowercased().hasPrefix("translategemma") }
    public init(endpoint: URL = Self.defaultEndpoint, model: String = Self.defaultModel, retention: Retention = .balanced) {
        self.endpoint = endpoint
        self.model = model
        self.retention = retention
    }
    public enum Retention: String, Codable, CaseIterable, Sendable {
        case short = "1m", balanced = "5m", extended = "15m"
        public var duration: Duration {
            switch self {
            case .short: .seconds(60)
            case .balanced: .seconds(300)
            case .extended: .seconds(900)
            }
        }
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
