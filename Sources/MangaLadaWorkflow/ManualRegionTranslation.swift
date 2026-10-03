import Foundation
import MangaLadaBallons
import MangaLadaCore
import MangaLadaRendering

@MainActor
struct ManualRegionTranslation {
    let engine: BallonsTranslatorEngine
    let session: JapaneseEngineSession
    let cache: TranslationCache

    func apply(to draft: MangaPageDraft, box: TextBox, kind: MangaTextKind, destinationURL: URL,
               configuration: LocalTranslatorConfiguration, typography: MangaTypography,
               status: @escaping @Sendable (String) async -> Void) async throws -> ProcessedMangaPage {
        await status("지정 영역 · 일본어 인식 중")
        let replaced = draft.translation.blocks.filter { ImageRegionSelection.containsCenter(box, of: $0.box) }
        let proposals = try proposedRegions(box: box, kind: kind, existing: replaced)
        var recognized = try await session.verifyProposedRegions(source: draft.translation.imageURL, regions: proposals)
        guard recognized.count == proposals.count, recognized.allSatisfy({ TextLanguageDetector.containsJapanese($0.originalText) }) else { throw ManualRegionError.noJapanese }
        for index in recognized.indices {
            recognized[index].textKind = kind; recognized[index].detectedFontSize = nil; recognized[index].userDefinedTextKind = true
            if let original = replaced.first(where: { $0.id == recognized[index].id }) {
                recognized[index].box = original.box; recognized[index].balloonShape = original.balloonShape
            }
        }
        await status("지정 영역 · 한국어 번역 중")
        let translated = try await TranslationPipeline(sourceLanguage: .japanese, targetLanguage: .korean)
            .translate(recognized, configuration: configuration)
        try Task.checkCancellation()
        var translation = draft.translation
        translation.blocks = MangaReadingOrder.sorted(draft.translation.blocks.filter { !ImageRegionSelection.containsCenter(box, of: $0.box) } + translated)
        let cleanURL = engine.inpaintedImageURL(runID: translation.imageFingerprint + "-manual")
        let candidate = cleanURL.deletingLastPathComponent().appendingPathComponent("manual-candidate.png")
        try FileManager.default.createDirectory(at: cleanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contentsOf: draft.cleanImageURL).write(to: candidate, options: .atomic)
        await status("지정 영역 · 원문 제거 중")
        try await engine.eraseSupplementalText(translated, cleanImageURL: candidate, bounded: true, maskSourceURL: draft.translation.imageURL)
        try Task.checkCancellation()
        let rendered = try PageImageRendering.render(translation: translation, cleanImageURL: candidate,
            destinationURL: destinationURL, typography: typography, wasCached: false)
        try Data(contentsOf: candidate).write(to: cleanURL, options: .atomic)
        try cache.save(translation)
        return ProcessedMangaPage(translation: rendered.translation, cleanImageURL: cleanURL,
                                 renderedImageURL: rendered.renderedImageURL, wasCached: false)
    }
    private func proposedRegions(box: TextBox, kind: MangaTextKind, existing: [TextBlock]) throws -> [TextBlock] {
        guard existing.count > 1 else {
            return [TextBlock(id: existing.first?.id ?? UUID(), box: box, originalText: "", textKind: kind, userDefinedBounds: box)]
        }
        let cells = try ImageRegionSelection.partitions(box, blocks: existing)
        return existing.map { block in
            TextBlock(id: block.id, box: block.box, originalText: "", textKind: kind, effectStyleID: block.effectStyleID, userDefinedBounds: cells[block.id])
        }
    }
}

public enum ManualRegionError: LocalizedError {
    case invalidBounds, noJapanese
    public var errorDescription: String? {
        switch self {
        case .invalidBounds: "이미지 안에서 글자와 배치 공간을 포함하도록 영역을 다시 드래그해주세요."
        case .noJapanese: "지정한 영역에서 일본어를 읽지 못했습니다. 글자가 선명하게 들어오도록 영역을 조절해주세요."
        }
    }
}
