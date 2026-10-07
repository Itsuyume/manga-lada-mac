import Foundation

@main
struct PackagedResourceChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { FileHandle.standardError.write(Data("Fixture cleanup failed: \(error)\n".utf8)) }
        }
        let appURL = root.appendingPathComponent("Fixture.app")
        let resources = appURL.appendingPathComponent("Contents/Resources")
        let bundleURL = resources.appendingPathComponent("FixtureResources.bundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let info: [String: String] = ["CFBundleIdentifier": "local.resourcefixture", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        try Data("packaged payload".utf8).write(to: bundleURL.appendingPathComponent("payload.txt"))
        guard let app = Bundle(url: appURL), let development = Bundle(url: bundleURL) else { throw CheckError.invalidFixture }

        for name in ["", "MissingBundle"] {
            do {
                _ = try PackageResourceBundle.load(named: name, in: app) { fatalError("Apps cannot use build resources") }
                throw CheckError.expectedMissingBundle
            } catch let error as CocoaError where error.code == .fileNoSuchFile { continue }
        }
        let packaged = try PackageResourceBundle.load(named: "FixtureResources", in: app) {
            fatalError("Packaged resources must not evaluate the development accessor")
        }
        guard let payload = packaged.url(forResource: "payload", withExtension: "txt"),
              try String(contentsOf: payload, encoding: .utf8) == "packaged payload" else { throw CheckError.wrongPayload }
        let package = try PackageResourceBundle.load(named: "FixtureResources", in: development) { development }
        guard package.bundleURL == development.bundleURL else { throw CheckError.wrongDevelopmentBundle }
        if CommandLine.arguments.count > 1 { try checkApplication(at: CommandLine.arguments[1]) }
        print("Packaged resources: missing/empty names, app payload, lazy development access, SwiftPM context PASS")
    }

    private static func checkApplication(at path: String) throws {
        guard let app = Bundle(path: path) else { throw CheckError.invalidFixture }
        let expected: [(String, String, String, String?)] = [("Core", "sound-effect-lexicon", "json", nil),
                        ("Rendering", "sound-effect-styles", "json", nil),
                        ("Rendering", "BlackHanSans-Regular", "ttf", "Fonts"),
                        ("Ballons", "japanese_engine_worker", "py", nil),
                        ("Ballons", "erase_supplemental_text", "py", nil)]
        for (module, name, fileExtension, subdirectory) in expected {
            let bundle = try PackageResourceBundle.load(named: "MangaLadaMac_MangaLada" + module, in: app) {
                fatalError("Installed apps cannot use SwiftPM build resources")
            }
            guard let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory),
                  try !Data(contentsOf: url).isEmpty else { throw CheckError.wrongPayload }
        }
        print("Installed app: lexicon, styles, font, OCR worker, erasure worker PASS")
    }

    private enum CheckError: Error {
        case invalidFixture, expectedMissingBundle, wrongPayload, wrongDevelopmentBundle
    }
}
