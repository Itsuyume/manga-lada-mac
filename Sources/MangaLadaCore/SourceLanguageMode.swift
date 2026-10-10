import Foundation

/// The reader's choice. `automatic` resolves each page to a concrete `LanguageCode`
/// before recognition; the pipeline itself always works with one known language.
public enum SourceLanguageMode: String, Codable, CaseIterable, Sendable {
    case automatic, japanese, english

    public init(fixed language: LanguageCode) {
        self = language == .english ? .english : .japanese
    }

    public var fixedLanguage: LanguageCode? {
        switch self {
        case .automatic: nil
        case .japanese: .japanese
        case .english: .english
        }
    }

    public var localizedName: String {
        switch self {
        case .automatic: "자동 감지"
        case .japanese: "일본어"
        case .english: "영어"
        }
    }

    /// Languages automatic mode can choose, in the order cached pages are looked up.
    public static let automaticCandidates: [LanguageCode] = [.japanese, .english]
    /// True when pages in this mode may take the Japanese path (and its optional models).
    public var allowsJapanese: Bool { self != .english }
    public var allowsEnglish: Bool { self != .japanese }
}

extension LocalTranslatorConfiguration {
    /// A copy fixed to a page's already-processed language, so follow-up requests on that page
    /// (selection retranslation, region drag) never re-detect or switch its cache keys.
    public func fixed(to language: LanguageCode) -> Self {
        var copy = self
        copy.sourceLanguageMode = SourceLanguageMode(fixed: language)
        copy.sourceLanguage = language
        return copy
    }
}
