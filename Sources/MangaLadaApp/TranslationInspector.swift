import MangaLadaCore
import MangaLadaRendering
import MangaLadaViewerUI
import SwiftUI

struct TranslationInspector: View {
    @ObservedObject var state: AppState
    @State private var draft: PageTranslation?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("번역 검수").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(state.currentIndex + 1)쪽").foregroundStyle(.secondary) }
            if state.currentResult != nil {
                Text("번호로 위치를 확인하세요. 분류가 다르면 종류를 바꾼 뒤 ‘수정 적용’을 누르세요.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(state.currentResult?.warnings ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let draft, !draft.blocks.isEmpty {
                editors(draft)
                Button("수정 적용", systemImage: "checkmark") { apply() }.disabled(state.isBusy)
                Button("현재 페이지 다시 번역", systemImage: "arrow.clockwise") { state.startTranslation(onlyCurrent: true, force: true) }.disabled(state.isBusy)
            } else if state.currentResult != nil {
                Text("인식된 글자가 없는 페이지입니다.").foregroundStyle(.secondary)
            } else {
                Text(state.processingIndex == state.currentIndex ? "일본어를 인식하고 번역하는 중입니다." : "이 페이지가 번역되면 문구를 수정할 수 있습니다.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let failure = state.failures[state.currentIndex] {
                Text(failure).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            if !state.failures.isEmpty { failureList }
            Divider()
            Button { state.chooseOutputFolder() } label: {
                Label(state.outputRoot?.lastPathComponent ?? "완성본 폴더 지정", systemImage: "folder").lineLimit(1)
            }.disabled(state.isBusy).help(state.outputRoot?.path ?? "완성본을 저장할 폴더를 선택해주세요.")
        }.font(.system(size: 12)).padding(16).background(Color(nsColor: .controlBackgroundColor))
            .onChange(of: state.currentResult?.translation, initial: true) { _, translation in draft = translation }
            .onChange(of: state.currentIndex) { _, _ in draft = state.currentResult?.translation }
    }
    private func editors(_ translation: PageTranslation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(translation.blocks.indices, id: \.self) { index in
                        editor(at: index).id(translation.blocks[index].id)
                    }
                }
            }
            .onChange(of: state.blockFocusRevision) { _, _ in
                if let id = state.selectedBlockID { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .top) } }
            }
            .onChange(of: state.selectedRegionNumbers) { _, numbers in
                if let number = numbers.first { proxy.scrollTo(translation.blocks[number - 1].id, anchor: .top) }
            }
        }
    }
    private func editor(at index: Int) -> some View {
        let block = draft?.blocks[index]
        let active = block.map { state.isBlockSelected($0.id) } ?? false
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { state.focusBlock(block?.id) } label: {
                    Text("\(index + 1)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(active ? Color.white : Color.secondary).frame(minWidth: 23, minHeight: 22)
                        .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain).help("이미지에서 \(index + 1)번 문구 표시")
                Picker("문구 종류", selection: kindBinding(index)) {
                    ForEach(MangaTextKind.allCases, id: \.self) { Text($0.regionLabel).tag($0) }
                }.labelsHidden().controlSize(.small).disabled(state.isBusy)
            }
            TextField("일본어 원문", text: originalBinding(index), axis: .vertical)
                .font(.system(size: 11)).foregroundStyle(.secondary).disabled(state.isBusy)
            Button("이 문구 다시 번역") { if let draft { state.retranslateBlock(in: draft, at: index) } }
                .font(.system(size: 10)).disabled(state.isBusy)
            if draft?.blocks[index].textKind == .soundEffect {
                Picker("효과음 스타일", selection: effectStyleBinding(index)) {
                    Text("전체 설정 따르기").tag("")
                    Text("원문에 맞춰 추천").tag("automatic")
                    ForEach(state.effectStyles) { Text($0.name).tag($0.id) }
                }.controlSize(.small).disabled(state.isBusy)
            }
            TextEditor(text: textBinding(index)).font(.system(size: 13)).frame(minHeight: 54, maxHeight: 100)
                .padding(4).background(.background, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(.quaternary) }
                .disabled(state.isBusy)
        }.padding(7).background(active ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(active ? Color.accentColor : Color.clear, lineWidth: 1) }
    }
    private var failureList: some View {
        DisclosureGroup("실패한 페이지 \(state.failures.count)개") {
            ScrollView { VStack(alignment: .leading) {
                ForEach(state.failures.keys.sorted(), id: \.self) { index in Button("\(index + 1)페이지 확인") { state.select(index) } }
            } }.frame(maxHeight: 160)
        }.font(.system(size: 11))
    }
    private func textBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft?.blocks[index].translatedText ?? "" }, set: { draft?.blocks[index].translatedText = $0 })
    }
    private func originalBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft?.blocks[index].originalText ?? "" }, set: { draft?.blocks[index].originalText = $0 })
    }
    private func kindBinding(_ index: Int) -> Binding<MangaTextKind> {
        Binding(get: { draft?.blocks[index].textKind ?? .dialogue }, set: {
            draft?.blocks[index].textKind = $0; draft?.blocks[index].userDefinedTextKind = true
        })
    }
    private func effectStyleBinding(_ index: Int) -> Binding<String> {
        Binding(get: { draft?.blocks[index].effectStyleID ?? "" }, set: { draft?.blocks[index].effectStyleID = $0.isEmpty ? nil : $0 })
    }
    private func apply() {
        guard let draft else { return }
        guard draft.blocks.allSatisfy({ !$0.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            state.errorMessage = "빈 번역 문구가 있습니다. 문구를 채워주세요."; return
        }
        do { try state.updateCurrentTranslation(draft) } catch { state.errorMessage = error.localizedDescription }
    }
}
