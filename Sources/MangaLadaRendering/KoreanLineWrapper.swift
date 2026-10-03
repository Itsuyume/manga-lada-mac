import Foundation

package enum KoreanLineWrapper {
    /// Exact line count, balanced word breaks; punctuation stays with the preceding word.
    package static func balanced(_ text: String, widths: [CGFloat], allowWordBreaks: Bool, measure: (String) -> CGFloat) -> [String] {
        guard let widest = widths.max(), widest > 0 else { return [] }
        if !allowWordBreaks, text.split(separator: " ").contains(where: { measure(String($0)) > widest }) { return [] }
        let units = text.split(separator: " ").flatMap { word -> [Unit] in
            if !allowWordBreaks { return [Unit(text: String(word), spaceBefore: true)] }
            return word.enumerated().map { Unit(text: String($0.element), spaceBefore: $0.offset == 0) }
        }
        guard !units.isEmpty, widths.count <= units.count else { return [] }
        var states = [0: Breaks(cost: 0, lines: [])]
        for (row, width) in widths.enumerated() {
            states = advance(states, units: units, width: width, remainingRows: widths.count - row - 1, measure: measure)
            if states.isEmpty { return [] }
        }
        return states[units.count]?.lines ?? []
    }

    private static func advance(_ states: [Int: Breaks], units: [Unit], width: CGFloat, remainingRows: Int,
                                measure: (String) -> CGFloat) -> [Int: Breaks] {
        var next: [Int: Breaks] = [:]
        for (start, state) in states {
            guard start < units.count else { continue }
            if start > 0, isClosingPunctuation(units[start].text), !isEmphasisTail(units[start...]) { continue }
            var line = ""
            for end in start..<units.count {
                line += (line.isEmpty || !units[end].spaceBefore ? "" : " ") + units[end].text
                let measured = measure(line)
                if measured > width { break }
                let remaining = units.count - end - 1
                if remaining < remainingRows { break }
                if remainingRows == 0, remaining > 0 { continue }
                let splitBefore = start > 0 && !units[start].spaceBefore
                let splitAfter = remaining > 0 && !units[end + 1].spaceBefore
                if hasSingleLetterFragment(units, start: start, end: end, splitBefore: splitBefore, splitAfter: splitAfter) { continue }
                let raggedness = pow(Double(1 - measured / width), 2)
                let orphanPenalty = line.filter { !$0.isWhitespace }.count == 1 ? 8.0 : 0
                let wordBreakPenalty = remaining > 0 && !units[end + 1].spaceBefore ? 0.8 : 0
                let cost = state.cost + raggedness + orphanPenalty + wordBreakPenalty
                if cost < (next[end + 1]?.cost ?? .infinity) {
                    next[end + 1] = Breaks(cost: cost, lines: state.lines + [line])
                }
            }
        }
        return next
    }

    private static func hasSingleLetterFragment(_ units: [Unit], start: Int, end: Int, splitBefore: Bool, splitAfter: Bool) -> Bool {
        let firstEnd = (start...end).dropFirst().first { units[$0].spaceBefore } ?? (end + 1)
        let lastStart = (start...end).last { units[$0].spaceBefore } ?? start
        let firstLetters = units[start..<firstEnd].reduce(0) { $0 + $1.text.filter { $0.isLetter || $0.isNumber }.count }
        let lastLetters = units[lastStart...end].reduce(0) { $0 + $1.text.filter { $0.isLetter || $0.isNumber }.count }
        return (splitBefore && firstLetters == 1) || (splitAfter && lastLetters == 1)
    }

    private static func isEmphasisTail(_ units: ArraySlice<Unit>) -> Bool {
        let text = units.map(\.text).joined()
        return text.count >= 2 && text.allSatisfy { ".…!?".contains($0) }
    }

    private static func isClosingPunctuation(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return ",.!?…)]}」』”’".contains(first)
    }
    private struct Unit { let text: String; let spaceBefore: Bool }
    private struct Breaks { let cost: Double; let lines: [String] }

    static func wrap(_ text: String, widths: [CGFloat], measure: (String) -> CGFloat) -> [String] {
        var lines: [String] = [], current = ""
        for word in text.split(separator: " ").map(String.init) {
            guard lines.count < widths.count else { return [] }
            let candidate = current.isEmpty ? word : current + " " + word
            if measure(candidate) <= widths[lines.count] { current = candidate; continue }
            if !current.isEmpty { lines.append(current); current = "" }
            guard lines.count < widths.count else { return [] }
            if measure(word) <= widths[lines.count] { current = word; continue }
            for character in word {
                guard lines.count < widths.count else { return [] }
                if !current.isEmpty, ",.!?…)]}」』”’".contains(character) { current.append(character); continue }
                let fragment = current + String(character)
                if !current.isEmpty, measure(fragment) > widths[lines.count] { lines.append(current); current = String(character) }
                else { current = fragment }
            }
        }
        if !current.isEmpty { lines.append(current) }
        guard lines.count <= widths.count, lines.enumerated().allSatisfy({ measure($0.element) <= widths[$0.offset] }) else { return [] }
        return lines
    }
}
