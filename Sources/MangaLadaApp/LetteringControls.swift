import MangaLadaCore
import SwiftUI

struct LetteringControls: View {
    @ObservedObject var state: AppState
    let block: TextBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("글자 방향", selection: Binding<TextDirection?>(
                get: { block.textDirection },
                set: { direction in
                    state.editReviewBlock(block.id) { $0.textDirection = direction }; state.scheduleLetteringPreview()
                }
            )) {
                Text(block.textKind == .soundEffect ? "자동 · 원문 방향" : "자동 · 말풍선 맞춤").tag(TextDirection?.none)
                Text("가로 줄 쌓기").tag(TextDirection?.some(.horizontal))
                Text("세로 · 글자 세우기").tag(TextDirection?.some(.vertical))
            }
            HStack(spacing: 5) {
                Text("크기")
                Button { setPercent(percent - 5) } label: { Image(systemName: "minus") }
                    .disabled(percent <= LetteringPreferences.percentRange.lowerBound).accessibilityLabel("글자 크기 줄이기")
                Slider(value: sizeBinding, in: LetteringPreferences.percentRange, step: 5)
                    .accessibilityLabel("글자 크기 드래그")
                Button { setPercent(percent + 5) } label: { Image(systemName: "plus") }
                    .disabled(percent >= LetteringPreferences.percentRange.upperBound).accessibilityLabel("글자 크기 키우기")
                TextField("크기", value: sizeBinding, format: .number.precision(.fractionLength(0)))
                    .frame(width: 42).multilineTextAlignment(.trailing).accessibilityLabel("글자 크기 백분율")
                Text("%")
            }
            HStack {
                Button("배치 영역 드래그", systemImage: "viewfinder") { state.beginLetteringPlacement(block.id) }
                Button("자동으로 복원") {
                    state.editReviewBlock(block.id) { $0.fontScale = nil; $0.textDirection = nil; $0.textLayoutBounds = nil; $0.textOffset = nil }
                    state.scheduleLetteringPreview()
                }.disabled(block.fontScale == nil && block.textDirection == nil && block.textLayoutBounds == nil && block.textOffset == nil)
            }
        }.font(.system(size: 10)).controlSize(.small)
            .help("자동 기준 크기의 40~240%입니다. 방향·크기·배치를 정한 뒤 수정 적용을 누르세요. 공간이 부족하면 크기를 줄여주세요.")
    }
    private var percent: Double { (block.fontScale ?? 1) * 100 }
    private var sizeBinding: Binding<Double> { Binding(get: { percent }, set: { setPercent($0) }) }
    private func setPercent(_ value: Double) {
        state.editReviewBlock(block.id) { $0.fontScale = value / 100 }
        state.scheduleLetteringPreview()
    }
}
