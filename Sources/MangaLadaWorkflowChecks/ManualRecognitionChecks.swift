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
        print("Manual recognition passed: symbols/Japanese/mixed order accepted; empty/non-Japanese/missing/extra/duplicate/wrong IDs rejected; inputs unchanged")
    }

    private static func rejects(_ recognized: [TextBlock], for proposals: [TextBlock]) throws {
        do { try ManualRegionTranslation.validateRecognition(recognized, for: proposals) }
        catch is ManualRegionError { return }
        throw Failure.acceptedInvalidInput
    }

    private enum Failure: Error { case changedInput, acceptedInvalidInput }
}
