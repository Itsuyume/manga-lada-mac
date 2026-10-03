import Foundation
import MangaLadaRendering

extension MangaLadaRenderingChecks {
    static func checkCurvedLineWrapping() throws {
        let measure: (String) -> CGFloat = { text in text.reduce(0) { $0 + ($1.isLetter || $1.isNumber ? 10 : 5) } }
        for (text, widths) in [("", [CGFloat(60)]), ("안녕", []), ("안녕", [0])] {
            try require(KoreanLineWrapper.balanced(text, widths: widths, allowWordBreaks: true, measure: measure).isEmpty,
                        "Empty text or unusable rows produced a layout.")
        }
        let text = "고마워, 할아버지...", widths: [CGFloat] = [60, 25, 60]
        let lines = KoreanLineWrapper.balanced(text, widths: widths, allowWordBreaks: true, measure: measure)
        try require(lines.count == widths.count, "Word fitting only the widest row could not use three curved rows.")
        try require(lines.joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace }, "Wrapping lost text.")
        for (line, width) in zip(lines, widths) {
            try require(measure(line) <= width && line.filter(\.isLetter).count > 1, "Text overflowed or left a single-letter fragment.")
            try require(!",.!?".contains(line.first ?? " "), "Closing punctuation started a line.")
        }
        let natural = KoreanLineWrapper.balanced(text, widths: [60, 60], allowWordBreaks: true, measure: measure)
        try require(natural == ["고마워,", "할아버지..."], "Unnecessary word breaks replaced natural wrapping.")
        print("Curved wrapping checks passed: empty/invalid rows, narrower middle row, no lost text, no single-letter fragments, natural word breaks")
    }
}
