import Foundation

/// Identity of the Manga Lada Claude edition. It installs beside the original Manga translator
/// and Manga Reader and never reads or writes their data, settings or Keychain item.
public enum MangaLadaEdition {
    public static let translatorName = "Manga Lada Claude"
    public static let readerName = "Manga Lada Claude Reader"
    public static let supportFolderName = "Manga Lada Claude"
    public static let geminiKeychainService = "local.mangaladaclaude.mac.gemini"

    /// Engine, models, caches, review drafts and configuration all live here.
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(supportFolderName, isDirectory: true)
    }
}
