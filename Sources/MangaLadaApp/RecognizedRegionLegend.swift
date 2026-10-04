import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

struct RecognizedRegionLegend: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Text("인식 영역").foregroundStyle(.secondary)
            ForEach(MangaTextKind.allCases, id: \.self) { kind in
                let blocks = state.currentReview?.blocks.filter { ($0.textKind ?? .dialogue) == kind } ?? []
                if !blocks.isEmpty {
                    Button { state.focusBlock(blocks[0].id) } label: {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(kind.regionColor).frame(width: 8, height: 8)
                            Text("\(kind.regionLabel) \(blocks.count)")
                        }
                    }.buttonStyle(.plain).help("해당 종류의 첫 문구 확인 · 검수에서 종류를 바꿀 수 있습니다")
                }
            }
            Spacer(minLength: 0)
        }.font(.system(size: 10)).padding(.horizontal, 20).padding(.vertical, 7).background(.bar)
    }
}
