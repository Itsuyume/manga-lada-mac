import MangaLadaCore
import SwiftUI

public extension MangaTextKind {
    var regionLabel: String { self == .dialogue ? "대사(말풍선)" : regionBadge }
    var regionBadge: String {
        switch self {
        case .dialogue: "대사"
        case .caption: "나레이션"
        case .title: "표지 제목"
        case .soundEffect: "효과음"
        }
    }
    var regionColor: Color {
        switch self {
        case .dialogue: MangaUI.accent
        case .caption: Color(red: 0.62, green: 0.40, blue: 0.92)
        case .title: Color(red: 0.90, green: 0.33, blue: 0.59)
        case .soundEffect: Color(red: 0.94, green: 0.49, blue: 0.15)
        }
    }
}
