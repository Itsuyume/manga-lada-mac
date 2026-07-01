import Foundation

public struct LocalTranslatorConfiguration: Equatable, Sendable {
    public let maxConcurrentRequests: Int

    public init(
        maxConcurrentRequests: Int = 4
    ) {
        self.maxConcurrentRequests = min(max(maxConcurrentRequests, 1), 8)
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
            maxConcurrentRequests: maxConcurrentRequests
        )
    }

    public var cacheKey: String {
        TranslationProvider.googleWeb.cacheKey
    }
}

private struct LocalTranslatorConfigurationFile: Decodable {
    let maxConcurrentRequests: Int?

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
