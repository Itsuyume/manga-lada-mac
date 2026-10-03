import AppKit
import CoreText
import Foundation

@MainActor
public enum SoundEffectFonts {
    /// Registers only in this process; does not change the Mac's installed font collection.
    public static func registerBundledFonts() throws {
        for (file, postScriptName) in [("BlackHanSans-Regular", "BlackHanSans-Regular"), ("NanumBrushScript-Regular", "NanumBrush"),
                                      ("NanumMyeongjo-Regular", "NanumMyeongjo")] {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else {
                throw SoundEffectLibraryError.missingResource(file)
            }
            // A lookup before registration can ask macOS to download a missing
            // font and block on FontRegistryUI. Register the bundled file first.
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                guard let cause = error?.takeRetainedValue() else { throw SoundEffectLibraryError.fontRegistration(file) }
                guard CFErrorGetDomain(cause) as String == kCTFontManagerErrorDomain as String,
                      CFErrorGetCode(cause) == CTFontManagerError.alreadyRegistered.rawValue else {
                    throw SoundEffectLibraryError.fontRegistration(String(describing: cause))
                }
            }
            guard NSFont(name: postScriptName, size: 14) != nil else { throw SoundEffectLibraryError.fontUnavailable(postScriptName) }
        }
    }
    public static var collectionDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            .appendingPathComponent("Manga translator/효과음 폰트집", isDirectory: true)
    }
}
