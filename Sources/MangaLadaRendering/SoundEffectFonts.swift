import AppKit
import CoreText
import Foundation

@MainActor
public enum SoundEffectFonts {
    /// Registers only in this process; does not change the Mac's installed font collection.
    public static func registerBundledFonts() throws {
        for (file, postScriptName) in [("BlackHanSans-Regular", "BlackHanSans-Regular"), ("NanumBrushScript-Regular", "NanumBrush"),
                                      ("NanumMyeongjo-Regular", "NanumMyeongjo")] {
            if NSFont(name: postScriptName, size: 14) != nil { continue }
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else {
                throw SoundEffectLibraryError.missingResource(file)
            }
            var error: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
                let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? file
                throw SoundEffectLibraryError.fontRegistration(reason)
            }
            guard NSFont(name: postScriptName, size: 14) != nil else { throw SoundEffectLibraryError.fontUnavailable(postScriptName) }
        }
    }
    public static var collectionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            .appendingPathComponent("Manga translator/효과음 폰트집", isDirectory: true)
    }
}
