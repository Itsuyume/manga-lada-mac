import Foundation
import MangaLadaCore

enum ModelRetentionChecks {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("settings.json")
        let missing = try LocalTranslatorConfiguration.load(configURL: file, environment: [:])
        try check(missing.ollama.retention == .balanced, "Missing settings did not use bounded balanced retention.")
        for json in ["{}", #"{"ollamaModel":"qwen3.5:9b"}"#, #"{"ollamaKeepAlive":null}"#] {
            try Data(json.utf8).write(to: file)
            let loaded = try LocalTranslatorConfiguration.load(configURL: file, environment: [:])
            try check(loaded.ollama.retention == .balanced, "Legacy or null retention did not migrate to the default.")
        }
        for value in [#""-1m""#, #""forever""#, "0", "-1"] {
            let data = Data("{\"ollamaKeepAlive\":\(value)}".utf8)
            try data.write(to: file)
            do {
                _ = try LocalTranslatorConfiguration.load(configURL: file, environment: [:])
                throw CheckError.failed("Unsupported or unbounded retention was accepted.")
            } catch is DecodingError { }
            try check(try Data(contentsOf: file) == data, "Reading invalid settings overwrote the user's file.")
        }
        let original = LocalTranslatorConfiguration()
        try check(OllamaConfiguration.Retention.allCases.map(\.duration) == [.seconds(60), .seconds(300), .seconds(900)],
                  "OCR session duration does not match the persisted model retention choices.")
        for retention in OllamaConfiguration.Retention.allCases {
            var edited = original; edited.ollama.retention = retention
            try edited.save(to: file)
            let restored = try LocalTranslatorConfiguration.load(configURL: file, environment: [:])
            try check(restored == edited, "Retention setting did not round-trip.")
            try check(restored.cacheKey == original.cacheKey && !restored.requiresRetranslation(comparedTo: original),
                      "Retention-only changes invalidate completed translations or review drafts.")
            try check(!original.requiresRetranslation(comparedTo: restored), "Runtime-setting comparison is asymmetric.")
            var model = restored; model.ollama.model = "qwen3.5:9b"
            var provider = restored; provider.provider = .geminiFlashLite
            var recognition = restored; recognition.enhanceSoundEffects = true
            for changed in [model, provider, recognition] {
                try check(changed.requiresRetranslation(comparedTo: restored), "A translation-affecting setting was ignored.")
            }
        }
        try check(original.ollama.retention == .balanced, "Comparing settings mutated the original value.")
        print("Model retention passed: legacy/null/invalid settings, bounded choices, round-trip, cache stability and translation-setting separation")
    }
    private static func check(_ condition: Bool, _ message: String) throws { if !condition { throw CheckError.failed(message) } }
    private enum CheckError: Error { case failed(String) }
}
