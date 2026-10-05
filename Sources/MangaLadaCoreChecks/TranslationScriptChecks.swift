import Foundation
import MangaLadaCore

enum TranslationScriptChecks {
    static func run() throws {
        let source = TextBlock(box: TextBox(x: 0.1, y: 0.1, width: 0.2, height: 0.3), originalText: "早く来てよね〜")
        // Replay the actual rejected response, without treating its wording as a correct translation.
        for text in ["빨리 와줄게〜", "빨리 와 줘～", "빨리 와 줘~", "빨리 와 줘…", "빨리·와 줘！"] {
            let result = try MangaNumberedPageResponse.decode("[R0] \(text)", blocks: [source])
            guard result[0].translatedText == text, result[0].box == source.box, result[0].id == source.id,
                  !TextLanguageDetector.containsJapanese(text) else { throw Failure.symbolRejected }
        }
        for text in ["빨리 来て", "빨리 와よ", "빨리 와ｱ", "빨리 와㍿", "빨리 와𠮷", "〜", "", "hello"] {
            do {
                _ = try MangaNumberedPageResponse.decode("[R0] \(text)", blocks: [source])
                throw Failure.wordAccepted
            } catch TranslationError.invalidPageResponse { }
        }
        for text in ["", "「」", "『』", "〇", "123", "한국어"] {
            guard !TextLanguageDetector.containsJapanese(text) else { throw Failure.symbolRejected }
        }
        guard source.translatedText.isEmpty else { throw Failure.inputChanged }
    }

    private enum Failure: Error { case symbolRejected, wordAccepted, inputChanged }
}
