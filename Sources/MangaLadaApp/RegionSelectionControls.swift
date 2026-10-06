import MangaLadaCore
import MangaLadaViewerUI
import SwiftUI

struct RegionSelectionControls: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 10) {
            Label(selectionLabel, systemImage: "cursorarrow.and.square.on.square.dashed")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                .layoutPriority(-1).padding(.leading, 6)
            if state.placementBlockID == nil {
                Picker("영역 종류", selection: $state.selectedRegionKind) {
                    ForEach([MangaTextKind.dialogue, .caption, .soundEffect], id: \.self) { Text($0.regionBadge).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize().disabled(state.isBusy)
            }
            Button("선택 지우기") { state.selectRegion(nil) }.buttonStyle(.borderless)
                .disabled(state.selectedRegion == nil || state.isBusy)
            if state.placementBlockID != nil {
                Button("이 영역에 배치", systemImage: "text.viewfinder") { state.stageLetteringPlacement() }
                    .buttonStyle(.borderedProminent).disabled(state.selectedRegion == nil || state.isBusy)
            } else {
                Button("선택 영역 번역", systemImage: "character.bubble.ja") { state.translateSelectedRegion() }
                    .buttonStyle(.borderedProminent).disabled(state.selectedRegion == nil || state.isBusy)
            }
        }.controlSize(.small).mangaFloatingBar()
    }
    private var selectionLabel: String {
        if let id = state.placementBlockID, let index = state.currentReview?.blocks.firstIndex(where: { $0.id == id }) {
            return "\(index + 1)번 글자가 들어갈 영역을 드래그하세요 · 번역 문구 유지"
        }
        guard state.selectedRegion != nil else { return "번호를 누르거나 글자와 배치 공간을 함께 드래그하세요" }
        let numbers = state.selectedRegionNumbers
        guard !numbers.isEmpty else { return "새 영역 선택 · 번역 후 번호가 붙습니다" }
        let label = numbers.prefix(8).map(String.init).joined(separator: "·") + (numbers.count > 8 ? "…" : "")
        return numbers.count > 1 ? "\(label)번 선택 · 각 말풍선을 나눠 번역합니다" : "\(label)번 문구 선택"
    }
}
