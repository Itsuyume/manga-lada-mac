import Foundation
import MangaLadaCore

enum AppPaths {
    /// Separate from the original app's `Manga Lada` folder; see `MangaLadaEdition`.
    static var support: URL { MangaLadaEdition.applicationSupport }
    static var archives: URL { support.appendingPathComponent("Archives") }
    static var configuration: URL { support.appendingPathComponent("translator-config.json") }
}
