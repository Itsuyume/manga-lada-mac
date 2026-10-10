import Foundation

/// A small, conservative catalog. Spoken words and user classifications stay intact.
public enum EnglishSoundEffects {
    private static let forms = [
        "BOOM": "쾅", "BANG": "탕", "CRASH": "와장창", "WHAM": "퍽", "POW": "퍽",
        "THUD": "쿵", "CLICK": "딸깍", "CLACK": "달칵", "WHOOSH": "휙", "SWISH": "슥",
        "SPLASH": "첨벙", "SPLAT": "철퍽", "KNOCK": "똑", "BUZZ": "윙", "ZAP": "찌릿",
        "RUMBLE": "우르르", "BEEP": "삐", "DING": "딩", "RING": "따르릉"
    ]

    public static func translation(for text: String) -> String? {
        let units = text.precomposedStringWithCompatibilityMapping.uppercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?…\n\t"))
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" }).map(String.init)
        guard let unit = units.first, (1...4).contains(units.count),
              units.allSatisfy({ $0 == unit }), let korean = forms[unit] else { return nil }
        return String(repeating: korean, count: units.count)
    }

    public static func inferKinds(_ blocks: [TextBlock], selectedIDs: Set<UUID>? = nil) -> [TextBlock] {
        blocks.map { block in
            guard selectedIDs?.contains(block.id) != false, block.balloonShape == nil,
                  block.userDefinedTextKind != true, block.userDefinedBounds == nil,
                  block.textKind != .title, block.textKind != .caption,
                  translation(for: block.originalText) != nil else { return block }
            var effect = block
            effect.textKind = .soundEffect
            return effect
        }
    }
}
