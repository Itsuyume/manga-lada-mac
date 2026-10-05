import Foundation
import MangaLadaCore

enum TranslationReviewChecks {
    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("drafts")
        let store = TranslationReviewStore(directory: directory)
        let page = fixture(root: root)
        try check(store.load(for: page) == nil, "Empty review storage produced a draft.")
        try store.save(page, comparedTo: page)
        try check(!FileManager.default.fileExists(atPath: directory.path), "Unchanged review created a file.")
        var draft = page
        draft.blocks[0].originalText = "空から雷の音が聞こえる。"
        draft.blocks[0].translatedText = "천둥이 가깝다."
        draft.blocks[0].textKind = .caption
        draft.blocks[0].userDefinedTextKind = true
        draft.blocks[1].effectStyleID = nil
        try store.save(draft, comparedTo: page)
        let reopened = TranslationReviewStore(directory: directory)
        try check(reopened.load(for: page) == draft, "Fresh store lost source, translation, kind or cleared style.")
        try latestResultsKeepUneditedFields(store: reopened, page: page, draft: draft)
        try removedUneditedRegion(store: store, page: page)
        try store.save(draft, comparedTo: page)
        try identityFailures(store: store, page: page, draft: draft)
        try emptyAndIndependentPages(store: store, page: page)
        try fileFailures(root: root, directory: directory, page: page, draft: draft)
        try interpretationReview(root: root, page: page)
        try letteringReview(root: root, page: page)
        print("TranslationReviewChecks passed")
    }

    private static func letteringReview(root: URL, page: PageTranslation) throws {
        let store = TranslationReviewStore(directory: root.appendingPathComponent("lettering"))
        var draft = page
        draft.blocks[1].textDirection = .vertical
        draft.blocks[1].fontScale = 0.8
        draft.blocks[1].textLayoutBounds = .init(x: 0.35, y: 0.5, width: 0.25, height: 0.3)
        draft.blocks[1] = try LetteringPreferences.moved(draft.blocks[1], by: .init(x: 0.05, y: -0.1))
        try store.save(draft, comparedTo: page)
        try check(store.load(for: page) == draft, "Direction, size, drag bounds or displacement lost on restart.")
        try check(JSONDecoder().decode(PageTranslation.self, from: JSONEncoder().encode(draft)) == draft, "Lettering cache roundtrip changed values.")
        for invalid in [Double.nan, .infinity, -1, 0.1, 3] {
            var bad = draft; bad.blocks[1].fontScale = invalid
            try expectFailure { try store.save(bad, comparedTo: page) }
            try check(store.load(for: page) == draft, "Invalid size destroyed a recoverable review.")
        }
        for delta in [TextOffset(x: 2, y: 0), .init(x: 0, y: -2), .init(x: Double.nan, y: 0)] {
            try expectFailure { _ = try LetteringPreferences.moved(draft.blocks[1], by: delta) }
        }
        var restored = draft
        restored.blocks[1].fontScale = nil; restored.blocks[1].textDirection = nil
        restored.blocks[1].textLayoutBounds = nil; restored.blocks[1].textOffset = nil
        try store.save(restored, comparedTo: draft)
        try check(store.load(for: draft) == restored, "Reset to automatic did not survive restart.")
        var latest = page; latest.blocks[1].box.y = 0.4
        try store.save(draft, comparedTo: page)
        var expected = draft; expected.blocks[1].box = latest.blocks[1].box
        try check(store.load(for: latest) == expected, "Review overwrote new OCR bounds.")
        let legacy = Data(#"{"id":"75E87718-392D-424F-86DA-29343125354C","box":{"x":0.1,"y":0.1,"width":0.3,"height":0.3},"originalText":"ドン","translatedText":"쿵","confidence":1}"#.utf8)
        let decoded = try JSONDecoder().decode(TextBlock.self, from: legacy)
        try check(decoded.textDirection == nil && decoded.fontScale == nil && decoded.textOffset == nil && decoded.textLayoutBounds == nil,
                  "Legacy region gained a manual override.")
        print("Lettering review checks passed: old caches, replay/reset, range/NaN/page-edge failures, no geometry mutation")
    }

    private static func interpretationReview(root: URL, page: PageTranslation) throws {
        let directory = root.appendingPathComponent("interpretation-draft")
        let store = TranslationReviewStore(directory: directory)
        var interpreted = page
        interpreted.blocks[0].maskedTextInterpretation = MaskedTextInterpretation(japanese: "推定した日本語", message: "뜻을 확인해주세요")
        try store.save(interpreted, comparedTo: page)
        try check(TranslationReviewStore(directory: directory).load(for: page) == interpreted,
                  "Interpretation-only change did not survive a review restart.")
        var edited = interpreted
        edited.blocks[0].originalText = "修正した日本語"
        try store.save(edited, comparedTo: interpreted)
        try check(store.load(for: interpreted) == edited && edited.blocks[0].maskedTextInterpretation == nil,
                  "Review restore kept an interpretation for an edited source.")
    }

    private static func removedUneditedRegion(store: TranslationReviewStore, page: PageTranslation) throws {
        var draft = page
        draft.blocks[0].translatedText = "새 문구"
        draft.blocks[0].box.x = 0.8
        try store.save(draft, comparedTo: page)
        var latest = page
        latest.blocks.removeLast()
        var expected = latest
        expected.blocks[0].translatedText = "새 문구"
        try check(store.load(for: latest) == expected, "Unedited region removal blocked restoration or draft geometry leaked.")
    }

    private static func latestResultsKeepUneditedFields(store: TranslationReviewStore, page: PageTranslation, draft: PageTranslation) throws {
        var latest = page
        latest.createdAt = Date(timeIntervalSince1970: 200)
        latest.blocks[0].box.x = 0.4
        latest.blocks[0].confidence = 0.95
        latest.blocks[1].translatedText = "우르릉!"
        latest.blocks[1].rotationDegrees = 12
        let added = TextBlock(box: TextBox(x: 0.2, y: 0.7, width: 0.2, height: 0.1), originalText: "雨", translatedText: "비")
        latest.blocks.append(added)
        latest.blocks.reverse()
        var expected = latest
        expected.blocks[2].originalText = draft.blocks[0].originalText
        expected.blocks[2].translatedText = draft.blocks[0].translatedText
        expected.blocks[2].textKind = draft.blocks[0].textKind
        expected.blocks[2].userDefinedTextKind = true
        expected.blocks[1].effectStyleID = nil
        try check(store.load(for: latest) == expected, "Draft overwrote fresh geometry, unedited text, added regions or current order.")
    }

    private static func identityFailures(store: TranslationReviewStore, page: PageTranslation, draft: PageTranslation) throws {
        var missing = page
        missing.blocks.removeFirst()
        try expectFailure { _ = try store.load(for: missing) }
        try check(store.load(for: page) == draft, "Failed restore destroyed the recoverable draft.")
        var duplicate = draft
        duplicate.blocks[1].id = duplicate.blocks[0].id
        try expectFailure { try store.save(duplicate, comparedTo: page) }
        var wrongPage = draft
        wrongPage.imageFingerprint = "other-page"
        try expectFailure { try store.save(wrongPage, comparedTo: page) }
        try check(store.load(for: page) == draft, "Rejected edit changed the stored draft.")
    }

    private static func emptyAndIndependentPages(store: TranslationReviewStore, page: PageTranslation) throws {
        var blank = page
        blank.blocks[0].translatedText = ""
        try store.save(blank, comparedTo: page)
        try check(store.load(for: page)?.blocks[0].translatedText == "", "In-progress empty text was discarded.")
        var second = page
        second.imageFingerprint = "second"
        var secondDraft = second
        secondDraft.blocks[1].translatedText = "다른 페이지 수정"
        try store.save(secondDraft, comparedTo: second)
        try store.save(page, comparedTo: page)
        try check(store.load(for: page) == nil && store.load(for: second) == secondDraft, "Revert affected another page.")
        try store.discard(fingerprint: second.imageFingerprint)
        try check(store.load(for: second) == nil, "Discard left the draft active.")
        var empty = page
        empty.blocks = []
        try store.save(empty, comparedTo: empty)
        try check(store.load(for: empty) == nil, "Empty page created a pending edit.")
    }

    private static func fileFailures(root: URL, directory: URL, page: PageTranslation, draft: PageTranslation) throws {
        let malformed = directory.appendingPathComponent("first.json")
        let badData = Data("{ broken json".utf8)
        try badData.write(to: malformed)
        try expectFailure { _ = try TranslationReviewStore(directory: directory).load(for: page) }
        try check(Data(contentsOf: malformed) == badData, "Unreadable draft was removed or rewritten.")
        let blocked = root.appendingPathComponent("not-a-directory")
        let marker = Data("preserve".utf8)
        try marker.write(to: blocked)
        try expectFailure { try TranslationReviewStore(directory: blocked).save(draft, comparedTo: page) }
        try check(Data(contentsOf: blocked) == marker, "Write failure changed an unrelated file.")
    }

    private static func fixture(root: URL) -> PageTranslation {
        PageTranslation(imageURL: root.appendingPathComponent("source.png"), imageFingerprint: "first", sourceLanguage: .japanese,
                        targetLanguage: .korean, createdAt: Date(timeIntervalSince1970: 100), blocks: [
            TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.7, height: 0.2), originalText: "雷が近い。", translatedText: "기존 문구", textKind: .dialogue),
            TextBlock(box: TextBox(x: 0.3, y: 0.5, width: 0.4, height: 0.2), originalText: "ゴロゴロ", translatedText: "우르릉", textKind: .soundEffect, effectStyleID: "rumble")
        ])
    }
    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckFailure(message: message) }
    }
    private static func expectFailure(_ operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw CheckFailure(message: "Invalid review or file boundary did not fail.")
    }
    private struct CheckFailure: Error { let message: String }
}
