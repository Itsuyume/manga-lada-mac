import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

struct RecognizedRegionLegend: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 6) {
            Text("인식 영역").foregroundStyle(.white.opacity(0.6))
            ForEach(MangaTextKind.allCases, id: \.self) { kind in
                let blocks = state.currentReview?.blocks.filter { ($0.textKind ?? .dialogue) == kind } ?? []
                if !blocks.isEmpty {
                    Button { state.focusBlock(blocks[0].id) } label: {
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(kind.regionColor).frame(width: 8, height: 8)
                            Text("\(kind.regionBadge) \(blocks.count)").monospacedDigit()
                        }.foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                    }.buttonStyle(.plain).help("\(kind.regionLabel) 첫 문구 확인 · 검수에서 종류를 바꿀 수 있습니다")
                }
            }
        }.font(.system(size: 11))
    }
}
