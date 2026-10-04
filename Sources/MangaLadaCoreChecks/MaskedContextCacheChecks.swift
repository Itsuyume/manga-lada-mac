import Foundation
import MangaLadaCore

extension NetworkBoundaryChecks {
    static func checkContextCacheLimits(root: URL, session: URLSession, configuration: LocalTranslatorConfiguration) async throws {
        try await checkAbstentionAndConcurrency(root: root, session: session, configuration: configuration)
        let directory = root.appendingPathComponent("entry-limit")
        let pipeline = contextPipeline(directory, session: session)
        let block = contextBlock("お○ぎりを食べよう。", y: 0.1)
        installContextResponse(terms: #"{"terms":[{"masked":"お○ぎり","expanded":"おにぎり"}]}"#,
                               translation: "[R0] 주먹밥을 먹자.")
        for index in 0...256 {
            _ = try await pipeline.translate([block], configuration: configuration, previousContext: "context-\(index)")
        }
        let cache = directory.appendingPathComponent("masked-context-v1.json")
        try check(try cacheEntryCount(cache) == 256, "Interpretation cache exceeded its entry budget.")
        let before = FixtureProtocol.state.count
        _ = try await pipeline.translate([block], configuration: configuration, previousContext: "context-256")
        try check(FixtureProtocol.state.count == before + 1, "Newest cached interpretation was evicted.")
        _ = try await pipeline.translate([block], configuration: configuration, previousContext: "context-0")
        try check(FixtureProtocol.state.count == before + 3, "Oldest interpretation was not evicted.")
        try await checkContextByteBudget(root: root, session: session, configuration: configuration)
    }

    private static func checkAbstentionAndConcurrency(root: URL, session: URLSession,
                                                     configuration: LocalTranslatorConfiguration) async throws {
        let directory = root.appendingPathComponent("abstention")
        let block = contextBlock("ア○スという会社です。", y: 0.1)
        installContextResponse(terms: #"{"terms":[]}"#, translation: "[R0] 아○스라는 회사예요.")
        for index in 0..<2 {
            let result = try await contextPipeline(directory, session: session).translate([block], configuration: configuration)
            try check(result[0].originalText == block.originalText && result[0].translatedText == "아○스라는 회사예요."
                      && result[0].maskedTextInterpretation?.japanese == nil
                      && result[0].maskedTextInterpretation?.message.contains("확정하지 못") == true,
                      "Abstention guessed a name or hid review status.")
            try check(FixtureProtocol.state.count == index + 2, "Abstention was not reused after reopening the cache.")
        }
        let concurrentDirectory = root.appendingPathComponent("concurrent")
        let pipeline = contextPipeline(concurrentDirectory, session: session)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask {
                    _ = try await pipeline.translate([block], configuration: configuration, previousContext: "concurrent-\(index)")
                }
            }
            try await group.waitForAll()
        }
        let file = concurrentDirectory.appendingPathComponent("masked-context-v1.json")
        try check(try cacheEntryCount(file) == 8, "Concurrent interpretations lost cached entries.")
        let before = FixtureProtocol.state.count
        let reopened = contextPipeline(concurrentDirectory, session: session)
        for index in 0..<8 {
            _ = try await reopened.translate([block], configuration: configuration, previousContext: "concurrent-\(index)")
        }
        try check(FixtureProtocol.state.count == before + 8, "Concurrent cache entries were not readable after reopening.")
    }

    private static func checkContextByteBudget(root: URL, session: URLSession,
                                              configuration: LocalTranslatorConfiguration) async throws {
        struct Term: Encodable { let masked: String; let expanded: String }
        struct Response: Encodable { let terms: [Term] }
        let terms = "一二三四五六七八".map { number in
            let prefix = String(repeating: "あ", count: 45) + String(number)
            return Term(masked: prefix + "○き", expanded: prefix + "いき")
        }
        let response = String(decoding: try JSONEncoder().encode(Response(terms: terms)), as: UTF8.self)
        installContextResponse(terms: response, translation: "[R0] 검수용 번역")
        let directory = root.appendingPathComponent("byte-limit")
        let pipeline = contextPipeline(directory, session: session)
        let block = contextBlock(terms.map(\.masked).joined(separator: "、"), y: 0.1)
        for index in 0..<220 {
            _ = try await pipeline.translate([block], configuration: configuration, previousContext: "bytes-\(index)")
        }
        let cache = directory.appendingPathComponent("masked-context-v1.json")
        try check(try Data(contentsOf: cache).count <= 524_288 && cacheEntryCount(cache) < 220,
                  "Large valid interpretations exceeded the disk budget.")
        let before = FixtureProtocol.state.count
        _ = try await contextPipeline(directory, session: session).translate([block], configuration: configuration, previousContext: "bytes-219")
        try check(FixtureProtocol.state.count == before + 1, "Size eviction discarded the newest result or broke disk loading.")
        print("Context cache limits passed: abstention, concurrent writes, 256 entries, 512 KiB and newest-result reuse")
    }

    private static func cacheEntryCount(_ file: URL) throws -> Int {
        struct Key: Decodable { let key: String }
        let entries = try JSONDecoder().decode([Key].self, from: Data(contentsOf: file))
        try check(Set(entries.map(\.key)).count == entries.count, "Disk cache contains duplicate keys.")
        return entries.count
    }
}
