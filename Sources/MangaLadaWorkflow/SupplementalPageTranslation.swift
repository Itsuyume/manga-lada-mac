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
    let pipeline: TranslationPipeline

    func apply(to base: ProcessedMangaPage, configuration: LocalTranslatorConfiguration, typography: MangaTypography,
               previousContext: String, force: Bool, status: @escaping @Sendable (String) async -> Void) async throws -> ProcessedMangaPage {
        let manual = base.translation.blocks.filter { $0.userDefinedBounds != nil }
        let boundsKey = manual.isEmpty ? "" : "-" + ImageFingerprint().make(for: try JSONEncoder().encode(manual.map(\.userDefinedBounds))).prefix(12)
        let key = base.translation.imageFingerprint + "-effects-v5" + boundsKey
        let cleanURL = engine.inpaintedImageURL(runID: key)
        let warningsURL = cleanURL.deletingLastPathComponent().appendingPathComponent("effects-warnings.json")
        let primaryURL = cleanURL.deletingLastPathComponent().appendingPathComponent("effects-primary.json")
        if !force, var stored = try cache.load(fingerprint: key), FileManager.default.fileExists(atPath: cleanURL.path) {
            let current = Dictionary(uniqueKeysWithValues: base.translation.blocks.map { ($0.id, $0) })
            let baseline = try JSONDecoder().decode(PageTranslation.self, from: Data(contentsOf: primaryURL))
            let beforeEffects = Dictionary(uniqueKeysWithValues: baseline.blocks.map { ($0.id, $0) })
            stored.blocks = stored.blocks.map { block in
                guard let primary = current[block.id], let prior = beforeEffects[block.id] else { return block }
                // Unchanged primary text must not overwrite a repaired effect with its old mistranslation.
                var updated = block.applyingReviewChanges(from: prior, to: primary)
                updated.userDefinedBounds = primary.userDefinedBounds
                updated.userDefinedOriginalText = primary.userDefinedOriginalText
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
        let existing = Dictionary(uniqueKeysWithValues: base.translation.blocks.map { ($0.id, $0) })
        let changed = augmented.blocks.filter { block in
            guard let old = existing[block.id] else { return true }
            return block.textKind == .soundEffect && old.textKind != .soundEffect
        }
        let translated = try await pipeline.translateSelected(Set(changed.map(\.id)), in: augmented.blocks,
            configuration: configuration, previousContext: previousContext)
        let extraIDs = Set(augmented.extras.map(\.id))
        let translatedExtras = translated.filter { extraIDs.contains($0.id) }
        var translation = base.translation
        translation.imageFingerprint = key
        translation.blocks = translated
        try FileManager.default.createDirectory(at: cleanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: base.cleanImageURL).write(to: cleanURL, options: .atomic)
        let effectCount = translatedExtras.filter { $0.textKind == .soundEffect }.count
        let otherCount = translatedExtras.count - effectCount
        await status("효과음 \(effectCount)곳 · 누락 문구 \(otherCount)곳 추가 · 원문 제거·식자 중")
        try await engine.eraseSupplementalText(translatedExtras, cleanImageURL: cleanURL)
        try Task.checkCancellation()
        var rendered = try PageImageRendering.render(translation: translation, cleanImageURL: cleanURL,
            destinationURL: base.renderedImageURL, typography: typography, wasCached: false)
        if augmented.unverified > 0 { rendered.warnings = ["위치를 확인하지 못한 효과음 \(augmented.unverified)곳은 원문을 유지했습니다."] }
        rendered.primaryTranslation = base.translation
        try JSONEncoder().encode(base.translation).write(to: primaryURL, options: .atomic)
        try JSONEncoder().encode(rendered.warnings).write(to: warningsURL, options: .atomic)
        try cache.save(translation)
        return rendered
    }
}
