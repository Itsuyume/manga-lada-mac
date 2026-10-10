import Foundation
import MangaLadaCore
import MangaLadaWorkflow

@MainActor
enum ManualRecognitionChecks {
    static func run() throws {
        let first = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.1), originalText: "")
        let second = TextBlock(box: TextBox(x: 0.6, y: 0.3, width: 0.2, height: 0.1), originalText: "")
        for text in ["．．．", "…", "！？", "「……」", "っ", "静かになった。"] {
            var recognized = first; recognized.originalText = text
            let before = recognized
            try ManualRegionTranslation.validateRecognition([recognized], for: [first])
            guard recognized == before else { throw Failure.changedInput }
        }
        var symbols = first; symbols.originalText = "!?"
        var dialogue = second; dialogue.originalText = "行こう。"
        try ManualRegionTranslation.validateRecognition([dialogue, symbols], for: [first, second])
        for text in ["", " \n ", "「」", "123", "Hello!", "한국어"] {
            var recognized = first; recognized.originalText = text
            try rejects([recognized], for: [first])
        }
        try rejects([], for: [])
        try rejects([], for: [first])
        try rejects([dialogue], for: [first, second])
        try rejects([symbols, dialogue], for: [first])
        try rejects([symbols, symbols], for: [first, second])
        try rejects([dialogue], for: [first])
        var moved = symbols; moved.box.x += 0.01
        try rejects([moved], for: [first])
        var uncertain = symbols; uncertain.recognitionAlternatives = ["!?", "!!"]
        try rejects([uncertain], for: [first])
        var english = first; english.originalText = "Hello, world!"
        try ManualRegionTranslation.validateRecognition([english], for: [first], sourceLanguage: .english)
        do {
            try ManualRegionTranslation.validateRecognition([dialogue], for: [second], sourceLanguage: .english)
            throw Failure.acceptedInvalidInput
        } catch ManualRegionError.noJapanese { }
        try checkLanguageCacheKeys()
        print("Manual recognition passed: symbols/Japanese/mixed order accepted; empty/non-Japanese/missing/extra/duplicate/wrong IDs rejected; inputs unchanged")
    }

    private static func checkLanguageCacheKeys() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("fingerprint source".utf8).write(to: source)
        let japanese = try JapanesePageKeys(imageURL: source, configuration: LocalTranslatorConfiguration(), context: "", title: "book")
        var settings = LocalTranslatorConfiguration(sourceLanguage: .english)
        let english = try JapanesePageKeys(imageURL: source, configuration: settings, context: "", title: "book")
        settings.japaneseOCR = .hayaiDetected
        let irrelevantJapaneseOCR = try JapanesePageKeys(imageURL: source, configuration: settings, context: "", title: "book")
        guard english.recognition != japanese.recognition, english.translation != japanese.translation,
              english.previous.isEmpty && english.previousRecognition == [english.recognitionBeforeCleanupUpdate],
              english.translation == irrelevantJapaneseOCR.translation && english.recognition == irrelevantJapaneseOCR.recognition else {
            throw Failure.acceptedInvalidInput
        }
    }

    private static func rejects(_ recognized: [TextBlock], for proposals: [TextBlock]) throws {
        do { try ManualRegionTranslation.validateRecognition(recognized, for: proposals) }
        catch is ManualRegionError { return }
        throw Failure.acceptedInvalidInput
    }

    private enum Failure: Error { case changedInput, acceptedInvalidInput }
}
