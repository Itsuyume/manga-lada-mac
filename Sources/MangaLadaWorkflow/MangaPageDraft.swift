import Foundation
import MangaLadaCore

/// Recognized page data is reviewable without claiming that a finished image exists.
public struct MangaPageDraft: Sendable {
    public var translation: PageTranslation
    public let cleanImageURL: URL
    public let wasCached: Bool
}

public struct MangaPageFailure: LocalizedError {
    public let draft: MangaPageDraft
    private let cause: any Error
    init(draft: MangaPageDraft, cause: any Error) { self.draft = draft; self.cause = cause }
    public var errorDescription: String? { cause.localizedDescription }
}

enum PageReviewReadiness {
    static func validate(_ edited: PageTranslation, against saved: PageTranslation) throws {
        guard edited.imageFingerprint == saved.imageFingerprint, edited.imageURL == saved.imageURL,
              edited.sourceLanguage == saved.sourceLanguage, edited.targetLanguage == saved.targetLanguage,
              Set(edited.blocks.map(\.id)).count == edited.blocks.count,
              Set(edited.blocks.map(\.id)) == Set(saved.blocks.map(\.id)) else { throw Failure.changedPage }
        guard edited.untranslatedBlockIDs.isEmpty else { throw Failure.untranslated(edited.untranslatedBlockIDs.count) }
    }
    private enum Failure: LocalizedError {
        case changedPage, untranslated(Int)
        var errorDescription: String? {
            switch self {
            case .changedPage: "페이지나 인식 영역이 바뀌어 수정본을 저장할 수 없습니다."
            case .untranslated(let count): "빈 번역 문구가 \(count)개 있습니다. 번역을 입력하거나 ‘번역 삭제 · 원본 유지’를 선택한 뒤 수정 적용을 눌러주세요."
            }
        }
    }
}
