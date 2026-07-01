import Foundation

public struct KoreanTranslationRefiner: Sendable {
    public init() {}

    public func refine(originalText: String, translatedText: String) -> String {
        let source = compactSource(originalText)
        var refined = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !refined.isEmpty else {
            return refined
        }

        for rule in Self.rules where rule.matches(source) {
            refined = rule.apply(to: refined)
        }

        return cleaned(refined)
    }

    private func compactSource(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
    }

    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: " \n", with: "\n")
            .replacingOccurrences(of: "\n ", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let rules: [TranslationRefinementRule] = [
        TranslationRefinementRule(
            sourceNeedles: ["まんこ", "マンコ", "おまんこ"],
            replacements: [
                .literal("오만코", "보지"),
                .literal("만코", "보지"),
                .literal("만화", "보지")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["子種"],
            replacements: [
                .literal("자종", "정액")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["殿方"],
            replacements: [
                .literal("전방", "남성분")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["劣情"],
            replacements: [
                .literal("열정", "욕정")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["肢体"],
            replacements: [
                .literal("팔다리", "몸")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["跡継ぎ"],
            replacements: [
                .literal("흔적", "후계자")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["孕ませ"],
            replacements: [
                .literal("암컷을 품는", "암컷을 임신시킬"),
                .literal("품는\n기회를", "임신시킬\n기회를"),
                .literal("꾸짖", "임신시키")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["無様な真似"],
            replacements: [
                .literal("무고한 흉내", "추태"),
                .literal("무의미한 모방", "추태"),
                .literal("무의미한 흉내", "추태")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["貧弱な精子"],
            replacements: [
                .literal("가난한\n정자", "보잘것없는\n정자"),
                .literal("가난한 정자", "보잘것없는 정자")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["さもしいこと"],
            replacements: [
                .literal("사소한 것", "천박한 짓"),
                .literal("사소한 일", "천박한 짓")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["縁のない"],
            replacements: [
                .literal("인연이없는", "인연 없는"),
                .literal("인연이 없는", "인연 없는")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["魅力的"],
            replacements: [
                .literal("매력적 인", "매력적인")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["天王寺"],
            replacements: [
                .literal("텐 노지", "텐노지")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["贅沢な"],
            replacements: [
                .literal("호화로운", "사치스러운")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["乱暴にしないで下さる"],
            replacements: [
                .literal("난폭하게하지", "난폭하게 하지"),
                .literal("마라?", "말아 주시겠어요?")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["ボランティア精神"],
            replacements: [
                .literal("자원\n봉사", "봉사"),
                .literal("자원 봉사", "봉사")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["我が事ながら感心"],
            replacements: [
                .literal("우리 일하면서\n감탄 해\n버릴거야.", "스스로도 감탄할 정도네요."),
                .literal("우리 일하면서 감탄 해 버릴거야.", "스스로도 감탄할 정도네요.")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["育む"],
            replacements: [
                .literal("키우기위한", "키우기 위한")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["チンポをしごく愉悦"],
            replacements: [
                .literal("자지를\n즐겁게\n즐기십시오.", "자지를 훑는 쾌락"),
                .literal("자지를 즐겁게 즐기십시오.", "자지를 훑는 쾌락")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["果てて"],
            replacements: [
                .literal("끝납니다", "사정합니다")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["ビクビク"],
            replacements: [
                .literal("BIKUBIKU와", "부르르"),
                .literal("BIKUBIKU", "부르르")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["受け止めます"],
            replacements: [
                .literal("받아\n들인다.", "받아들입니다."),
                .literal("받아 들인다.", "받아들입니다.")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["こすりつけ"],
            replacements: [
                .literal("정액을\n문지릅니다.", "정액을 문질러 묻힙니다."),
                .literal("정액을 문지릅니다.", "정액을 문질러 묻힙니다."),
                .literal("문지릅니다.", "문질러 묻힙니다.")
            ]
        ),
        TranslationRefinementRule(
            sourceNeedles: ["哀れですわ"],
            replacements: [
                .literal("슬픔이에요", "불쌍하네요")
            ]
        )
    ]
}

private struct TranslationRefinementRule: Sendable {
    let sourceNeedles: [String]
    let replacements: [TranslationReplacement]

    func matches(_ compactSource: String) -> Bool {
        sourceNeedles.contains { compactSource.contains($0) }
    }

    func apply(to text: String) -> String {
        replacements.reduce(text) { current, replacement in
            current.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.value,
                options: replacement.options
            )
        }
    }
}

private struct TranslationReplacement: Sendable {
    let pattern: String
    let value: String
    let options: String.CompareOptions

    static func literal(_ pattern: String, _ value: String) -> TranslationReplacement {
        TranslationReplacement(pattern: pattern, value: value, options: [])
    }
}
