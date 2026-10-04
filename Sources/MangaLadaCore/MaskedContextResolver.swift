import Foundation

/// Local hypotheses are cached by the exact request context, never promoted to a global glossary.
public actor MaskedContextResolver {
    private struct Entry: Codable {
        let key: String
        let resolution: MaskedContextResolution
        let created: Date
    }
    private struct RequestContext: Encodable { let version: Int; let model: String; let source: String; let context: String }
    private let fileURL: URL
    private var entries: [String: Entry]?
    private let maximumEntries = 256
    private let maximumBytes = 524_288

    public init(directory: URL) { fileURL = directory.appendingPathComponent("masked-context-v1.json") }

    func interpret(source: String, context: String, configuration: OllamaConfiguration, session: URLSession) async throws -> String {
        try Task.checkCancellation()
        let request = RequestContext(version: 1, model: configuration.model, source: source, context: String(context.prefix(2_000)))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let key = ImageFingerprint().make(for: data)
        try load()
        if let cached = entries?[key] { return try cached.resolution.applying(to: source) }
        let resolution = try await OllamaChatClient(configuration: configuration, session: session).validated(
            system: MaskedContextResolution.instruction, user: String(decoding: data, as: UTF8.self),
            schema: MaskedContextResolution.schema, outputTokens: 512) {
                try MaskedContextResolution.decode($0, source: source)
            }
        try Task.checkCancellation()
        try save(Entry(key: key, resolution: resolution, created: Date()))
        return try resolution.applying(to: source)
    }

    private func load() throws {
        guard entries == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { entries = [:]; return }
        let data = try Data(contentsOf: fileURL)
        guard data.count <= maximumBytes else { throw CacheError.invalidSize }
        let stored = try JSONDecoder().decode([Entry].self, from: data)
        guard stored.count <= maximumEntries, Set(stored.map(\.key)).count == stored.count else { throw CacheError.invalidEntries }
        entries = Dictionary(uniqueKeysWithValues: stored.map { ($0.key, $0) })
    }

    private func save(_ entry: Entry) throws {
        var updated = entries ?? [:]
        updated[entry.key] = entry
        var recent = Array(updated.values.sorted { $0.created > $1.created }.prefix(maximumEntries))
        let encoder = JSONEncoder()
        var data = try encoder.encode(recent)
        while data.count > maximumBytes && recent.count > 1 {
            recent.removeLast(); data = try encoder.encode(recent)
        }
        guard data.count <= maximumBytes else { throw CacheError.invalidSize }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        entries = Dictionary(uniqueKeysWithValues: recent.map { ($0.key, $0) })
    }

    private enum CacheError: LocalizedError {
        case invalidSize, invalidEntries
        var errorDescription: String? { "문맥 해석 캐시의 크기나 항목이 올바르지 않습니다. 기존 파일은 보존했습니다." }
    }
}
