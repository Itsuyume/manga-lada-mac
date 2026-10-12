import Foundation
import MangaLadaCore

enum TranslateGemmaBatchChecks {
    static func run() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let blocks = (0..<25).map { index in
            TextBlock(box: .init(x: 0.1, y: Double(index)/30, width: 0.3, height: 0.02), originalText: "Line \(index)",
                      translatedText: "기존 \(index)", fontScale: 0.8)
        }
        FixtureProtocol.state.install { request in
            let body = try JSONDecoder().decode(Probe.self, from: NetworkBoundaryChecks.body(request))
            try check(body.messages.count == 1 && body.messages[0].content.contains("Earlier chapter context."), "Batch lost context or added an unsupported system role")
            try check(body.format.properties["translations"]?.maxItems == body.format.properties["translations"]?.minItems, "Batch schema did not constrain its region count")
            return try response(body.messages[0].content)
        }
        let translator = TranslateGemmaPageTranslator(session: session, sourceLanguage: .english)
        let translated = try await translator.translatePage(blocks, previousContext: "Earlier chapter context.")
        try check(FixtureProtocol.state.count == 3 && translated.count == blocks.count, "Long page did not use bounded requests")
        for (index, block) in translated.enumerated() {
            try check(block.translatedText == "번역 \(index)" && block.id == blocks[index].id && block.box == blocks[index].box
                      && block.originalText == blocks[index].originalText && block.fontScale == blocks[index].fontScale,
                      "Batch numbering lost text identity, order or review metadata")
        }
        FixtureProtocol.state.install { request in
            try response(JSONDecoder().decode(Probe.self, from: NetworkBoundaryChecks.body(request)).messages[0].content)
        }
        _ = try await translator.translatePage(Array(blocks.prefix(13)))
        try check(FixtureProtocol.state.count == 2, "Thirteen regions did not split at the twelve-region boundary")
        let empty = try await translator.translatePage([])
        try check(empty.isEmpty && FixtureProtocol.state.count == 2, "Empty input called the provider")
        do { _ = try await translator.translatePage([blocks[0], blocks[0]]); throw BoundaryCheckError.failed("Duplicate source IDs accepted") }
        catch TranslationSelectionError.duplicateRegions { }
        let cancelled = Task { try await translator.translatePage(blocks) }; cancelled.cancel()
        do { _ = try await cancelled.value; throw BoundaryCheckError.failed("Cancelled batch returned success") }
        catch is CancellationError { }
        try check(FixtureProtocol.state.count == 2, "Invalid or cancelled input reached the provider")
        FixtureProtocol.state.install { request in
            try response(JSONDecoder().decode(Probe.self, from: NetworkBoundaryChecks.body(request)).messages[0].content)
        }
        let selected = TranslateGemmaPageTranslator(session: session, selectedIDs: [blocks[12].id], sourceLanguage: .english)
        let updated = try await selected.translatePage(blocks)
        try check(FixtureProtocol.state.count == 1 && updated[12].translatedText == "번역 12", "Selection translated unrelated batches")
        for index in blocks.indices where index != 12 { try check(updated[index] == blocks[index], "Selection changed its context-only neighbors") }
        FixtureProtocol.state.install { request in
            if FixtureProtocol.state.count > 1 { return try FixtureProtocol.ollamaReply("{\"translations\":[{\"id\":0,\"text\":\"불완전한 응답\",\"kind\":\"dialogue\"}]}") }
            return try response(JSONDecoder().decode(Probe.self, from: NetworkBoundaryChecks.body(request)).messages[0].content)
        }
        do { _ = try await translator.translatePage(blocks); throw BoundaryCheckError.failed("Failed batch returned partial success") }
        catch TranslationError.invalidPageResponse { }
        try check(FixtureProtocol.state.count == 3, "A failed batch retried indefinitely")
        print("TranslateGemma batches passed: count boundary, complete output, ID/order/review preservation, page context, selected regions and failed-batch rejection")
    }

    private static func response(_ prompt: String) throws -> (Int, Data) {
        let expression = try NSRegularExpression(pattern: #"(?m)^\[R(\d+)\] Line (\d+)$"#)
        let matches = expression.matches(in: prompt, range: NSRange(prompt.startIndex..<prompt.endIndex, in: prompt))
        try check(!matches.isEmpty && matches.count <= 12, "A request exceeded twelve regions")
        let rows = try matches.map { match -> Entry in
            guard let id = Range(match.range(at: 1), in: prompt), let number = Int(prompt[id]),
                  let source = Range(match.range(at: 2), in: prompt) else {
                throw BoundaryCheckError.failed("Missing fixture input")
            }
            // A transport-valid but wrong kind must not turn a sentence into
            // decorative lettering. The specialist keeps source/default kinds.
            return Entry(id: number, text: "번역 \(prompt[source])", kind: .soundEffect)
        }
        return try FixtureProtocol.ollamaReply(String(decoding: JSONEncoder().encode(Response(translations: rows)), as: UTF8.self))
    }
    private struct Probe: Decodable { let messages: [NetworkBoundaryChecks.Message]; let format: Format }
    private struct Format: Decodable { let properties: [String: Limit] }
    private struct Limit: Decodable { let minItems: Int; let maxItems: Int }
    private struct Response: Encodable { let translations: [Entry] }
    private struct Entry: Encodable { let id: Int; let text: String; let kind: MangaTextKind }
    private static func check(_ value: Bool, _ message: String) throws { try NetworkBoundaryChecks.check(value, message) }
}
