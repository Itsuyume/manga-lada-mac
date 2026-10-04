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
        print("TranslationReviewChecks passed")
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
