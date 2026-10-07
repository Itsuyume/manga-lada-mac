import Foundation
import MangaLadaCore

public struct SoundEffectStyle: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let usage: String
    public let sample: String
    public let fontName: String
    public let figmaFamily: String
    public let figmaStyle: String
    public let tracking: Double
    public let shear: Double
    public let widthScale: Double
    public let outline: Double
    public let hollow: Bool
}

/// This JSON also generates the Figma specimen and the offline font collection.
public struct SoundEffectLibrary: Sendable {
    public let styles: [SoundEffectStyle]
    public init(data: Data) throws {
        let decoded = try JSONDecoder().decode([SoundEffectStyle].self, from: data)
        guard !decoded.isEmpty, Set(decoded.map(\.id)).count == decoded.count,
              decoded.allSatisfy({ !$0.id.isEmpty && !$0.fontName.isEmpty && $0.widthScale > 0 && $0.widthScale <= 2 &&
                  abs($0.shear) <= 0.5 && abs($0.tracking) <= 0.5 && $0.outline >= 0 && $0.outline <= 12 }) else {
            throw SoundEffectLibraryError.invalidCatalog
        }
        styles = decoded
    }
    public static func standard() throws -> SoundEffectLibrary {
        let resources = try PackageResourceBundle.load(named: "MangaLadaMac_MangaLadaRendering") { Bundle.module }
        guard let url = resources.url(forResource: "sound-effect-styles", withExtension: "json") else {
            throw SoundEffectLibraryError.missingResource("sound-effect-styles.json")
        }
        return try SoundEffectLibrary(data: Data(contentsOf: url))
    }
    public func style(id: String) throws -> SoundEffectStyle {
        guard let style = styles.first(where: { $0.id == id }) else { throw SoundEffectLibraryError.unknownStyle(id) }
        return style
    }
    public func automaticStyle(original: String, translated: String) throws -> SoundEffectStyle {
        let text = original + " " + translated
        let rules: [(String, String)] = [
            ("ごろん|ゴロン|もじ|モジ|뒹굴|꼼지락|머뭇", "handwritten"),
            ("ドキ|두근|쿵쾅", "heartbeat"), ("ゴゴ|고오|우르|드르|부르", "rumble"),
            ("キラ|반짝|샤라|사르르", "sparkle"), ("ヒソ|소곤|속닥|속삭", "whisper"),
            ("シーン|정적|스산|오싹", "ominous"), ("シャ|シュ|싹|슉|휘익", "cut"),
            ("ザ|サラ|사락|찰랑|바스락", "soft"), ("ガリ|긁|으득|삐걱", "scratch"),
            ("ダダ|タタ|다다|타다|쏴|후다", "rush"), ("きゃ|キャ|으악|꺄|아악", "shout")
        ]
        return try style(id: rules.first(where: { text.range(of: $0.0, options: .regularExpression) != nil })?.1 ?? "impact")
    }
}

public enum SoundEffectLibraryError: LocalizedError {
    case invalidCatalog, missingResource(String), unknownStyle(String), fontUnavailable(String), fontRegistration(String)
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: "효과음 폰트집의 스타일 설정이 올바르지 않습니다."
        case .missingResource(let name): "효과음 폰트집 파일이 없습니다: \(name)"
        case .unknownStyle(let id): "효과음 스타일을 찾을 수 없습니다: \(id)"
        case .fontUnavailable(let name): "글꼴을 사용할 수 없습니다: \(name)"
        case .fontRegistration(let reason): "효과음 글꼴을 준비하지 못했습니다: \(reason)"
        }
    }
}
