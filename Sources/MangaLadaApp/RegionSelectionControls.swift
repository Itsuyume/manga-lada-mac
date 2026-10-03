import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

struct RegionSelectionControls: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 12) {
            Label(selectionLabel, systemImage: "cursorarrow.and.square.on.square.dashed")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Picker("영역 종류", selection: $state.selectedRegionKind) {
                ForEach([MangaTextKind.dialogue, .caption, .soundEffect], id: \.self) { Text($0.regionLabel).tag($0) }
            }.labelsHidden().frame(width: 140).disabled(state.isBusy)
            Button("선택 지우기") { state.selectRegion(nil) }.disabled(state.selectedRegion == nil || state.isBusy)
            Button("선택 영역 번역", systemImage: "character.bubble.ja") { state.translateSelectedRegion() }
                .buttonStyle(.borderedProminent).disabled(state.selectedRegion == nil || state.isBusy)
        }.controlSize(.small).padding(.horizontal, 18).padding(.vertical, 8).background(.bar)
    }
    private var selectionLabel: String {
        guard state.selectedRegion != nil else { return "번호를 누르거나 글자와 배치 공간을 함께 드래그하세요" }
        let numbers = state.selectedRegionNumbers
        guard !numbers.isEmpty else { return "새 영역 선택 · 번역 후 번호가 붙습니다" }
        let label = numbers.prefix(8).map(String.init).joined(separator: "·") + (numbers.count > 8 ? "…" : "")
        return numbers.count > 1 ? "\(label)번 선택 · 각 말풍선을 나눠 번역합니다" : "\(label)번 문구 선택"
    }
}
