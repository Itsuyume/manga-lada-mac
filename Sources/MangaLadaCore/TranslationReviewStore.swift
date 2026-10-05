import Foundation

/// Pending reviews are separate from committed translation caches and rendered images.
/// The app's main actor serializes writes. Each file atomically contains its baseline and edits.
public struct TranslationReviewStore {
    private let cachePaths: TranslationCache
    public init(directory: URL) { cachePaths = TranslationCache(cacheDirectory: directory) }

    public func load(for current: PageTranslation) throws -> PageTranslation? {
        let url = cachePaths.cacheFileURL(fingerprint: current.imageFingerprint)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let review = try JSONDecoder().decode(Review.self, from: Data(contentsOf: url))
        let restored = try review.applying(to: current)
        return restored == current ? nil : restored
    }

    public func save(_ edited: PageTranslation, comparedTo baseline: PageTranslation) throws {
        let review = Review(baseline: baseline, edited: edited)
        let restored = try review.applying(to: baseline)
        guard restored != baseline else { try discard(fingerprint: baseline.imageFingerprint); return }
        let url = cachePaths.cacheFileURL(fingerprint: baseline.imageFingerprint)
        let data = try JSONEncoder().encode(review)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func discard(fingerprint: String) throws {
        let url = cachePaths.cacheFileURL(fingerprint: fingerprint)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private struct Review: Codable {
        let baseline: PageTranslation
        let edited: PageTranslation

        func applying(to current: PageTranslation) throws -> PageTranslation {
            try validate(current)
            let before = Dictionary(uniqueKeysWithValues: baseline.blocks.map { ($0.id, $0) })
            let after = Dictionary(uniqueKeysWithValues: edited.blocks.map { ($0.id, $0) })
            let changedIDs = Set(edited.blocks.filter { block in
                guard let original = before[block.id] else { return false }
                return Self.hasChanges(from: original, to: block)
            }.map(\.id))
            guard changedIDs.isSubset(of: Set(current.blocks.map(\.id))) else { throw ReviewError.changedRegions }
            var result = current
            result.blocks = current.blocks.map { block in
                guard let original = before[block.id], let draft = after[block.id] else { return block }
                return block.applyingReviewChanges(from: original, to: draft)
            }
            return result
        }

        private func validate(_ current: PageTranslation) throws {
            guard baseline.imageFingerprint == edited.imageFingerprint, baseline.imageFingerprint == current.imageFingerprint,
                  baseline.sourceLanguage == edited.sourceLanguage, baseline.targetLanguage == edited.targetLanguage,
                  baseline.sourceLanguage == current.sourceLanguage, baseline.targetLanguage == current.targetLanguage,
                  Set(baseline.blocks.map(\.id)) == Set(edited.blocks.map(\.id)) else { throw ReviewError.changedRegions }
            for page in [baseline, edited, current] {
                guard Set(page.blocks.map(\.id)).count == page.blocks.count else { throw ReviewError.changedRegions }
            }
        }

        private static func hasChanges(from original: TextBlock, to draft: TextBlock) -> Bool {
            original.originalText != draft.originalText || original.translatedText != draft.translatedText ||
                original.textKind != draft.textKind || original.userDefinedTextKind != draft.userDefinedTextKind ||
                original.effectStyleID != draft.effectStyleID || original.maskedTextInterpretation != draft.maskedTextInterpretation
        }

    }
    private enum ReviewError: LocalizedError {
        case changedRegions
        var errorDescription: String? {
            "인식 영역이 달라 임시 수정을 복원하지 못했습니다. 임시 수정 파일은 보존했습니다."
        }
    }
}
