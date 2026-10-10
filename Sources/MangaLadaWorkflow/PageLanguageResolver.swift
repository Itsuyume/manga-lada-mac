import Foundation
import MangaLadaCore
import MangaLadaVision

/// Resolves automatic mode to one concrete language per page. A page that already has a
/// recognition or translation cache keeps the language it was processed in (no OCR, no model
/// call); only an unseen page is read once with platform OCR. Fixed modes pass through.
@MainActor
struct PageLanguageResolver {
    let cache: TranslationCache

    func resolve(_ configuration: LocalTranslatorConfiguration, imageURL: URL, previousContext: String, bookTitle: String,
                 status: @Sendable (String) async -> Void) async throws -> LocalTranslatorConfiguration {
        var resolved = configuration
        if let fixed = configuration.sourceLanguageMode.fixedLanguage {
            resolved.sourceLanguage = fixed
            return resolved
        }
        for language in SourceLanguageMode.automaticCandidates {
            resolved.sourceLanguage = language
            let keys = try JapanesePageKeys(imageURL: imageURL, configuration: resolved, context: previousContext, title: bookTitle)
            let known = [keys.translation, keys.recognition] + keys.previousRecognition + keys.previous
            if known.contains(where: { FileManager.default.fileExists(atPath: cache.cacheFileURL(fingerprint: $0).path) }) {
                return resolved
            }
        }
        await status("원문 언어 확인 중")
        let observations = try await VisionOCRService().recognizeText(in: imageURL, recognitionLanguages: ["ja-JP", "en-US"])
        // Too little text to decide (blank or art-only pages) keeps the established Japanese path.
        resolved.sourceLanguage = TextLanguageDetector.detectSourceLanguage(in: observations.map(\.originalText), fallback: .japanese)
        return resolved
    }
}
