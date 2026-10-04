import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering

/// Optional effects operate on a copy after the primary page is safely rendered.
@MainActor
struct SupplementalPageTranslation {
    let engine: BallonsTranslatorEngine
    let recognitionSession: JapaneseEngineSession
    let cache: TranslationCache

    func apply(to base: ProcessedMangaPage, configuration: LocalTranslatorConfiguration, typography: MangaTypography,
               previousContext: String, force: Bool, status: @escaping @Sendable (String) async -> Void) async throws -> ProcessedMangaPage {
        let manual = base.translation.blocks.filter { $0.userDefinedBounds != nil }
        let boundsKey = manual.isEmpty ? "" : "-" + ImageFingerprint().make(for: try JSONEncoder().encode(manual.map(\.userDefinedBounds))).prefix(12)
        let key = base.translation.imageFingerprint + "-effects-v4" + boundsKey
        let cleanURL = engine.inpaintedImageURL(runID: key)
        let warningsURL = cleanURL.deletingLastPathComponent().appendingPathComponent("effects-warnings.json")
        if !force, var stored = try cache.load(fingerprint: key), FileManager.default.fileExists(atPath: cleanURL.path) {
            let current = Dictionary(uniqueKeysWithValues: base.translation.blocks.map { ($0.id, $0) })
            stored.blocks = stored.blocks.map { block in
                guard let primary = current[block.id] else { return block }
                var updated = block; updated.translatedText = primary.translatedText; updated.effectStyleID = primary.effectStyleID
                updated.userDefinedBounds = primary.userDefinedBounds
                updated.originalText = primary.originalText; updated.userDefinedOriginalText = primary.userDefinedOriginalText
                if let kind = primary.textKind { updated.textKind = kind }
                return updated
            }
            var rendered = try PageImageRendering.render(translation: stored, cleanImageURL: cleanURL,
                destinationURL: base.renderedImageURL, typography: typography, wasCached: base.wasCached)
            rendered.warnings = try JSONDecoder().decode([String].self, from: Data(contentsOf: warningsURL))
            rendered.primaryTranslation = base.translation
            try cache.save(stored)
            return rendered
        }
        await status("대사 저장 완료 · 로컬 시각 모델로 효과음 보완 중")
        let augmented = try await SupplementalJapaneseOCR.recognize(in: base.translation.imageURL, existing: base.translation.blocks,
                                                                    retention: configuration.ollama.retention) { proposals in
            try await recognitionSession.verifyProposedRegions(source: base.translation.imageURL, regions: proposals,
                                                                idleTimeout: configuration.ollama.retention.duration)
        }
        try Task.checkCancellation()
        let pipeline = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean)
        let translatedExtras = try await pipeline.translate(augmented.extras, configuration: configuration, previousContext: previousContext)
        let byID = Dictionary(uniqueKeysWithValues: translatedExtras.map { ($0.id, $0) })
        var translation = base.translation
        translation.imageFingerprint = key
        translation.blocks = augmented.blocks.map { byID[$0.id] ?? $0 }
        try FileManager.default.createDirectory(at: cleanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: base.cleanImageURL).write(to: cleanURL, options: .atomic)
        await status("효과음 추가 인식 \(translatedExtras.count)곳 · 원문 제거·식자 중")
        try await engine.eraseSupplementalText(translatedExtras, cleanImageURL: cleanURL)
        try Task.checkCancellation()
        var rendered = try PageImageRendering.render(translation: translation, cleanImageURL: cleanURL,
            destinationURL: base.renderedImageURL, typography: typography, wasCached: false)
        if augmented.unverified > 0 { rendered.warnings = ["위치를 확인하지 못한 효과음 \(augmented.unverified)곳은 원문을 유지했습니다."] }
        rendered.primaryTranslation = base.translation
        try JSONEncoder().encode(rendered.warnings).write(to: warningsURL, options: .atomic)
        try cache.save(translation)
        return rendered
    }
}
