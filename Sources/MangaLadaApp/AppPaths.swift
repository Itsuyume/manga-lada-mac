import Foundation

enum AppPaths {
    // Keep the existing data location and bundle identity during the visible-name migration.
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Manga Lada")
    }
    static var archives: URL { support.appendingPathComponent("Archives") }
    static var configuration: URL { support.appendingPathComponent("translator-config.json") }
}
