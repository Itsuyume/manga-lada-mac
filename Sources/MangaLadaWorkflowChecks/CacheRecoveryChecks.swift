import Foundation
import MangaLadaCore
import MangaLadaWorkflow

/// Manual-region placement and cache recovery, using production types and real cache files.
enum CacheRecoveryChecks {
    static func run() throws {
        try overlappingManualRegions()
        try siblingTranslationKeys()
        try siblingAndUnreadableCacheFiles()
    }

    private static func overlappingManualRegions() throws {
        let firstBounds = TextBox(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        let secondBounds = TextBox(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        var first = TextBlock(box: firstBounds, originalText: "一", translatedText: "하나")
        first.userDefinedBounds = firstBounds
        var second = TextBlock(box: secondBounds, originalText: "二", translatedText: "둘")
        second.userDefinedBounds = secondBounds
        let covered = TextBlock(box: .init(x: 0.15, y: 0.15, width: 0.1, height: 0.1), originalText: "旧")
        let movedIdentity = TextBlock(id: first.id, box: .init(x: 0.7, y: 0.7, width: 0.1, height: 0.1), originalText: "移")
        let unrelated = TextBlock(box: .init(x: 0.7, y: 0.1, width: 0.1, height: 0.1), originalText: "外")
        let placed = MangaPageProcessor.placingManualRegions([first, second], over: [covered, movedIdentity, unrelated])
        try require(Set(placed.map(\.id)).count == placed.count, "Manual placement produced duplicate region identifiers.")
        try require(Set(placed.map(\.id)) == [first.id, second.id, unrelated.id],
                    "Overlapping manual regions removed each other or kept covered OCR.")
        try require(placed.first { $0.id == first.id }?.originalText == "一" && placed.first { $0.id == second.id }?.translatedText == "둘",
                    "Manual review text was replaced by OCR.")
        try require(MangaPageProcessor.placingManualRegions([], over: [covered, unrelated]) == [covered, unrelated],
                    "Pages without manual regions were changed.")
    }

    private static func siblingTranslationKeys() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([4, 5, 6]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let first = try JapanesePageKeys(imageURL: url, configuration: .init(), context: "", title: "A")
        let retitled = try JapanesePageKeys(imageURL: url, configuration: .init(), context: "page 4", title: "B")
        let hayai = try JapanesePageKeys(imageURL: url, configuration: .init(japaneseOCR: .hayai), context: "", title: "A")
        try require(first.translation != retitled.translation && retitled.sharesTranslationRequest(first.translation),
                    "A retitled book or edited previous page cannot find its reviewed translation.")
        try require(!first.sharesTranslationRequest(first.translation), "The current key was treated as a sibling.")
        try require(!first.sharesTranslationRequest(hayai.translation) && !hayai.sharesTranslationRequest(first.translation),
                    "Different OCR policies shared a translation.")
        try require(!first.sharesTranslationRequest(first.recognition) && !first.sharesTranslationRequest(first.translation + "x"),
                    "Recognition or malformed keys matched a translation request.")
        let family = String(hayai.translation.dropLast(12 + "-hayai-v3".count))
        let sameVersion = hayai.previous.prefix(hayai.previousSameVersionCount)
        try require(first.previousSameVersionCount == 0 && !sameVersion.isEmpty && sameVersion.allSatisfy { $0.hasPrefix(family) }
                    && hayai.previous.dropFirst(sameVersion.count).allSatisfy { !$0.hasPrefix(family) },
                    "Same-version previous keys are not the leading entries.")
    }

    private static func siblingAndUnreadableCacheFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cache-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TranslationCache(cacheDirectory: directory)
        try require(try cache.newestEntry { _ in true } == nil, "A missing cache directory produced an entry.")
        let block = TextBlock(box: .init(x: 0.1, y: 0.1, width: 0.2, height: 0.2), originalText: "検", translatedText: "검수")
        let older = PageTranslation(imageURL: URL(fileURLWithPath: "/page.png"), imageFingerprint: "page-a",
                                    sourceLanguage: .japanese, targetLanguage: .korean,
                                    createdAt: Date(timeIntervalSince1970: 1_700_000_000), blocks: [block])
        try cache.save(older)
        let unreadable = directory.appendingPathComponent("page-b.json")
        try Data("{".utf8).write(to: unreadable)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: cache.cacheFileURL(fingerprint: "page-a").path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: unreadable.path)
        try require(try cache.newestEntry { $0.hasPrefix("page-") } == older, "An unreadable newer sibling hid a readable review.")
        try require(try cache.newestEntry { $0 == "other" } == nil, "An unrelated entry matched.")
        do { _ = try cache.load(fingerprint: "page-b"); throw Failure.failed("An unreadable requested entry was accepted.") }
        catch is DecodingError { }
        try cache.quarantine(fingerprint: "page-b")
        try require(try cache.load(fingerprint: "page-b") == nil, "Quarantine left the unreadable entry in place.")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        guard let moved = names.first(where: { $0.hasPrefix("page-b.unreadable-") }) else {
            throw Failure.failed("Quarantine deleted the unreadable entry.")
        }
        try require(try Data(contentsOf: directory.appendingPathComponent(moved)) == Data("{".utf8), "Quarantine changed the unreadable bytes.")
        try require(try cache.load(fingerprint: "page-a") == older, "Quarantine changed another entry.")
        try cache.quarantine(fingerprint: "missing")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.failed(message) }
    }
    private enum Failure: LocalizedError {
        case failed(String)
        var errorDescription: String? { switch self { case .failed(let message): message } }
    }
}
