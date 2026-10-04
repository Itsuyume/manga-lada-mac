import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering
import MangaLadaVision

public struct ProcessedMangaPage: Sendable {
    public var translation: PageTranslation
    public let cleanImageURL: URL
    public let renderedImageURL: URL
    public let wasCached: Bool
    public var warnings: [String] = []
    public var primaryTranslation: PageTranslation?
}

/// Owns detection/translation/cache/render orchestration; no UI state or page navigation.
@MainActor
public final class MangaPageProcessor {
    private let engine: BallonsTranslatorEngine
    private let recognitionSession: JapaneseEngineSession
    private let cache: TranslationCache
    public let textTranslator: TranslationPipeline

    public init(applicationSupportDirectory: URL) {
        let adapter = BallonsTranslatorEngine.standard(applicationSupportDirectory: applicationSupportDirectory)
        engine = adapter; recognitionSession = JapaneseEngineSession(engine: adapter)
        cache = TranslationCache(cacheDirectory: applicationSupportDirectory.appendingPathComponent("Cache"))
        textTranslator = TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean,
            maskedResolver: MaskedContextResolver(directory: applicationSupportDirectory.appendingPathComponent("ContextInterpretations")))
    }

    public func process(imageURL: URL, destinationURL: URL, configuration: LocalTranslatorConfiguration,
                        typography: MangaTypography, previousContext: String = "", bookTitle: String = "", force: Bool = false,
                        status: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> ProcessedMangaPage {
        try Task.checkCancellation()
        let draft = try await preparePage(imageURL: imageURL, configuration: configuration, previousContext: previousContext,
                                          bookTitle: bookTitle, force: force, status: status)
        let result: ProcessedMangaPage
        do {
            result = try PageImageRendering.render(translation: draft.translation, cleanImageURL: draft.cleanImageURL,
                destinationURL: destinationURL, typography: typography, wasCached: draft.wasCached)
        } catch { throw MangaPageFailure(draft: draft, cause: error) }
        guard configuration.enhanceSoundEffects else { return result }
        do {
            return try await SupplementalPageTranslation(engine: engine, recognitionSession: recognitionSession, cache: cache, pipeline: textTranslator).apply(to: result, configuration: configuration,
                typography: typography, previousContext: previousContext, force: force, status: status)
        } catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            var saved = result
            saved.warnings = ["대사는 저장했습니다. 효과음 보완을 완료하지 못했습니다: \(error.localizedDescription)"]
            await status(saved.warnings[0])
            return saved
        }
    }

    private func preparePage(imageURL: URL, configuration: LocalTranslatorConfiguration, previousContext: String, bookTitle: String,
                             force: Bool, status: @escaping @Sendable (String) async -> Void) async throws -> MangaPageDraft {
        let keys = try JapanesePageKeys(imageURL: imageURL, configuration: configuration, context: previousContext, title: bookTitle)
        let cleanURL = engine.inpaintedImageURL(runID: keys.recognition)
        let storedCurrent = try cache.load(fingerprint: keys.translation)
        if !force, var translated = storedCurrent, FileManager.default.fileExists(atPath: cleanURL.path) {
            await status("캐시에서 불러와 글자 배치 중")
            translated.imageURL = imageURL
            if RecognitionCacheMigration.hasUnverifiedPunctuation(in: translated.blocks) {
                let recognized = try cache.load(fingerprint: keys.recognition)
                translated.blocks = RecognitionCacheMigration.verifyPunctuation(in: translated.blocks, recognized: recognized?.blocks)
            }
            let manual = engine.inpaintedImageURL(runID: keys.translation + "-manual")
            let selected = translated.blocks.contains { $0.userDefinedBounds != nil } && FileManager.default.fileExists(atPath: manual.path) ? manual : cleanURL
            return MangaPageDraft(translation: translated, cleanImageURL: selected, wasCached: true)
        }
        var recognized = try await recognition(imageURL: imageURL, key: keys.recognition, previousKeys: keys.previousRecognition, cleanURL: cleanURL,
                                               retention: configuration.ollama.retention, status: status)
        recognized.blocks = JapaneseRegionMerger.speechRegions(recognized.blocks)
        let storedPrior = try storedCurrent ?? previousTranslation(keys.previous)
        let manualBlocks = storedPrior?.blocks.filter { $0.userDefinedBounds != nil } ?? []
        for manual in manualBlocks {
            guard let bounds = manual.userDefinedBounds else { continue }
            var updated = manual
            let match = recognized.blocks.first { $0.id == manual.id }
                ?? recognized.blocks.first { ImageRegionSelection.containsCenter(bounds, of: $0.box) }
            updated.balloonShape = match?.balloonShape
            recognized.blocks.removeAll { ImageRegionSelection.containsCenter(bounds, of: $0.box) }
            recognized.blocks.append(updated)
        }
        recognized.blocks = MangaReadingOrder.sorted(recognized.blocks)
        for index in recognized.blocks.indices where recognized.blocks[index].textKind == .title {
            recognized.blocks[index].originalText = JapaneseTitleResolver.resolve(optical: recognized.blocks[index].originalText, bookTitle: bookTitle)
        }
        try Task.checkCancellation()
        let reusable = force ? nil : storedPrior
        let migrated = reusable.flatMap { RecognitionCacheMigration.reuse($0, for: recognized.blocks) }
        let baseline = PageTranslation(imageURL: imageURL, imageFingerprint: keys.translation,
            sourceLanguage: .japanese, targetLanguage: .korean, blocks: migrated ?? recognized.blocks)
        let selectedClean = try await manualCleanImage(for: baseline, sourceCleanURL: cleanURL)
        let blocks: [TextBlock]
        if let migrated, migrated.allSatisfy({ !$0.translatedText.isEmpty }) {
            await status("기존 번역 문구 재사용 · 말풍선 배치 계산 중"); blocks = migrated
        } else {
            await status("\(configuration.provider.displayName) · 페이지 문맥 번역 중")
            let reviewed = Dictionary(uniqueKeysWithValues: (migrated ?? []).filter { !$0.translatedText.isEmpty }.map { ($0.id, $0) })
            do {
                let translated = try await textTranslator.translate(baseline.blocks, configuration: configuration, previousContext: previousContext)
                blocks = translated.map { reviewed[$0.id] ?? $0 }
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                throw MangaPageFailure(draft: MangaPageDraft(translation: baseline, cleanImageURL: selectedClean, wasCached: false), cause: error)
            }
        }
        try Task.checkCancellation()
        let translation = PageTranslation(imageURL: imageURL, imageFingerprint: keys.translation,
                                          sourceLanguage: .japanese, targetLanguage: .korean,
                                          blocks: RecognitionCacheMigration.verifyPunctuation(in: blocks, recognized: recognized.blocks))
        try cache.save(translation)
        await status("말풍선·효과음에 글자 맞추는 중")
        return MangaPageDraft(translation: translation, cleanImageURL: selectedClean, wasCached: false)
    }
    private func previousTranslation(_ keys: [String]) throws -> PageTranslation? {
        for key in keys { if let value = try cache.load(fingerprint: key) { return value } }
        return nil
    }
    private func manualCleanImage(for translation: PageTranslation, sourceCleanURL: URL) async throws -> URL {
        let manual = translation.blocks.filter { $0.userDefinedBounds != nil }
        guard !manual.isEmpty else { return sourceCleanURL }
        let destination = engine.inpaintedImageURL(runID: translation.imageFingerprint + "-manual")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: sourceCleanURL).write(to: destination, options: .atomic)
        try await engine.eraseSupplementalText(manual, cleanImageURL: destination, bounded: true, maskSourceURL: translation.imageURL)
        return destination
    }

    public func translateRegion(imageURL: URL, destinationURL: URL, box: TextBox, kind: MangaTextKind,
                                configuration: LocalTranslatorConfiguration, typography: MangaTypography, bookTitle: String = "",
                                status: @escaping @Sendable (String) async -> Void = { _ in }) async throws -> ProcessedMangaPage {
        guard ImageRegionSelection.validates(box), box.width >= 0.001, box.height >= 0.001 else { throw ManualRegionError.invalidBounds }
        let draft = try await preparePage(imageURL: imageURL, configuration: configuration, previousContext: "", bookTitle: bookTitle,
                                           force: false, status: status)
        return try await ManualRegionTranslation(engine: engine, session: recognitionSession, cache: cache, pipeline: textTranslator).apply(
            to: draft, box: box, kind: kind, destinationURL: destinationURL, configuration: configuration, typography: typography, status: status)
    }

    public func applyEdits(to result: ProcessedMangaPage, translation: PageTranslation,
                           typography: MangaTypography) throws -> ProcessedMangaPage {
        let translation = try reviewedTranslation(translation, comparedTo: result.translation)
        var edited = try PageImageRendering.render(translation: translation, cleanImageURL: result.cleanImageURL,
                                                  destinationURL: result.renderedImageURL, typography: typography, wasCached: true)
        edited.warnings = result.warnings
        if var primary = result.primaryTranslation {
            let updates = Dictionary(uniqueKeysWithValues: translation.blocks.map { ($0.id, $0) })
            primary.blocks = primary.blocks.map { updates[$0.id] ?? $0 }
            try cache.save(primary)
            edited.primaryTranslation = primary
        }
        try cache.save(translation)
        return edited
    }

    public func finishReview(of draft: MangaPageDraft, translation: PageTranslation, destinationURL: URL,
                             typography: MangaTypography) throws -> ProcessedMangaPage {
        let translation = try reviewedTranslation(translation, comparedTo: draft.translation)
        let result = try PageImageRendering.render(translation: translation, cleanImageURL: draft.cleanImageURL,
                                                   destinationURL: destinationURL, typography: typography, wasCached: draft.wasCached)
        try cache.save(translation)
        return result
    }

    private func reviewedTranslation(_ translation: PageTranslation, comparedTo baseline: PageTranslation) throws -> PageTranslation {
        try PageReviewReadiness.validate(translation, against: baseline)
        let saved = Dictionary(uniqueKeysWithValues: baseline.blocks.map { ($0.id, $0) })
        var translation = translation
        translation.blocks = translation.blocks.map { block in
            guard let original = saved[block.id] else { return block }
            var updated = block
            if original.originalText != block.originalText { updated.userDefinedOriginalText = true }
            if original.originalText != block.originalText || original.translatedText != block.translatedText
                || original.textKind != block.textKind || original.effectStyleID != block.effectStyleID
                || original.box != block.box || original.userDefinedBounds != block.userDefinedBounds {
                updated.verifiedPunctuationBounds = nil
            }
            return updated
        }
        translation.blocks = RecognitionCacheMigration.verifyPunctuation(in: translation.blocks, recognized: baseline.blocks)
        return translation
    }

    private func recognition(imageURL: URL, key: String, previousKeys: [String], cleanURL: URL,
                             retention: OllamaConfiguration.Retention,
                             status: @escaping @Sendable (String) async -> Void) async throws -> PageTranslation {
        if let stored = try cache.load(fingerprint: key), FileManager.default.fileExists(atPath: cleanURL.path) { return stored }
        let prior = try previousTranslation(previousKeys)
        let lexicon = try JapaneseSoundEffectLexicon.bundled()
        await status("일본어 글자·효과음 위치 대조 중")
        let observations = try await VisionOCRService().recognizeText(in: imageURL, recognitionLanguages: ["ja-JP"], effectLexicon: lexicon)
        try Task.checkCancellation()
        await status(prior == nil ? "일본어 글자 검출 · 만화 OCR · 원문 제거 중" : "기존 일본어 인식 재사용 · 원문 복원 갱신 중")
        var result = try await recognitionSession.recognizeAndClean(source: imageURL, runID: key, priorBlocks: prior?.blocks,
            opticalCandidates: observations, idleTimeout: retention.duration)
        try Task.checkCancellation()
        if result.blocks.contains(where: { JapaneseHorizontalOCR.canRefine($0) }) {
            await status("가로 일본어 인식 대조 중")
            let refined = JapaneseHorizontalOCR.reconcile(result.blocks, observations: observations)
            if refined != result.blocks {
                // The first erase pass used uncorrected manga OCR. Reconcile its
                // ink extent too, using the resident engine and the same source.
                await status("보완한 원문의 끝 글자까지 제거 중")
                result = try await recognitionSession.recognizeAndClean(source: imageURL, runID: key,
                    priorBlocks: refined, opticalCandidates: observations, idleTimeout: retention.duration)
            }
            try Task.checkCancellation()
        }
        result.blocks = lexicon.inferKinds(result.blocks)
        if prior == nil { result.blocks = try await GraphicalTitleRecognition.repair(in: imageURL, blocks: result.blocks, retention: retention) }
        try cache.save(result)
        return result
    }
}
