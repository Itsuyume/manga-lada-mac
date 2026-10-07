import Foundation

/// Apps load their signed resources; SwiftPM executables use their development bundle.
public enum PackageResourceBundle {
    public static func load(named name: String, in application: Bundle = .main,
                            developmentBundle: () -> Bundle) throws -> Bundle {
        guard application.bundleURL.pathExtension.lowercased() == "app" else {
            return developmentBundle()
        }
        guard !name.isEmpty,
              let url = application.url(forResource: name, withExtension: "bundle"),
              let bundle = Bundle(url: url) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: name + ".bundle"])
        }
        return bundle
    }
}
