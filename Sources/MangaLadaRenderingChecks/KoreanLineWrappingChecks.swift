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
        let tiedMeasure: (String) -> CGFloat = { CGFloat($0.count) }
        let repeated = (0..<100).map { _ in
            KoreanLineWrapper.balanced("가가 나나 다다", widths: [8, 8], allowWordBreaks: false, measure: tiedMeasure)
        }
        try require(repeated.allSatisfy { $0 == ["가가", "나나 다다"] }, "Equal-cost wrapping changed between saved renders")
        for text in ["고마워,\n할아버지...", "고마워,\r\n할아버지..."] {
            for splitWords in [false, true] {
                try require(KoreanLineWrapper.balanced(text, widths: [60, 90], allowWordBreaks: splitWords, measure: measure)
                            == ["고마워,", "할아버지..."], "Explicit user line breaks were rebalanced.")
            }
        }
        try require(KoreanLineWrapper.balanced("안녕\n\n친구", widths: [50, 50, 50], allowWordBreaks: true, measure: measure)
                    == ["안녕", "", "친구"], "Intentional empty line disappeared.")
        for widths: [CGFloat] in [[90], [90, 20], [90, 0], [90, .infinity], [90, .nan]] {
            try require(KoreanLineWrapper.balanced("고마워,\n할아버지...", widths: widths, allowWordBreaks: true, measure: measure).isEmpty,
                        "Explicit layout was silently rewrapped or used invalid rows.")
        }
        print("Curved wrapping checks passed: empty/invalid rows, narrower middle row, no lost text, no single-letter fragments, natural word breaks")
    }
}
