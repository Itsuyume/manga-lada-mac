import Foundation

public struct MangaTypography: Codable, Equatable, Sendable {
    public var dialogueFontName: String
    public var effectFontName: String
    public var fontScale: Double
    /// nil preserves typography settings written before the effect library existed.
    public var effectStyleID: String?
    public init(dialogueFontName: String = "AppleSDGothicNeo-Bold", effectFontName: String = "AppleSDGothicNeo-Heavy", fontScale: Double = 1.0,
                effectStyleID: String? = "automatic") {
        self.dialogueFontName = dialogueFontName
        self.effectFontName = effectFontName
        self.fontScale = fontScale
        self.effectStyleID = effectStyleID
    }
}
