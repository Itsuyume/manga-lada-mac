import MangaLadaCore
import MangaLadaRendering
import MangaLadaViewerUI
import SwiftUI

struct TranslationInspector: View {
    @ObservedObject var state: AppState
    private var draft: PageTranslation? { state.currentReview }
    private var isPending: Bool { state.pendingPages[state.currentIndex] != nil }
    private var editingDisabled: Bool { state.isBusy || state.isLoading || state.reviewErrors[state.currentIndex] != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("번역 검수").font(.system(size: 13, weight: .semibold)); Spacer(); Text("\(state.currentIndex + 1)쪽").foregroundStyle(.secondary) }
            if draft != nil {
                Text(isPending ? "인식한 원문을 수정하거나 번역을 직접 입력할 수 있습니다. 모든 문구를 채운 뒤 ‘수정 적용’을 누르세요."
                     : "번호로 위치를 확인하세요. 분류가 다르면 종류를 바꾼 뒤 ‘수정 적용’을 누르세요.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(state.currentResult?.warnings ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            reviewNotice
            if let draft, !draft.blocks.isEmpty {
                if !draft.maskedTextReviewIDs.isEmpty {
                    Button("가림표 \(draft.maskedTextReviewIDs.count)개 Qwen 재번역", systemImage: "arrow.clockwise") {
                        state.retranslateMaskedWords()
                    }.disabled(editingDisabled).help("표시한 문구의 이전 해석 캐시를 건너뛰고 다시 판단합니다. 나머지 검수 문구는 유지됩니다.")
                }
                if isPending, !draft.untranslatedBlockIDs.isEmpty {
                    Button("빈 문구 \(draft.untranslatedBlockIDs.count)개 번역", systemImage: "character.bubble") {
                        state.translatePendingWords()
                    }.disabled(editingDisabled).help("입력한 번역은 유지하고, 번역이 비어 있는 문구만 처리합니다.")
                }
                editors(draft)
                HStack {
                    Button("수정 적용", systemImage: "checkmark") { apply() }.disabled(editingDisabled)
                    if state.hasCurrentReview { discardButton }
                }
            } else if draft != nil {
                Text("인식된 글자가 없는 페이지입니다.").foregroundStyle(.secondary)
                if isPending {
                    Button("이미지 다시 저장", systemImage: "square.and.arrow.down") { apply() }.disabled(editingDisabled)
                }
                if state.hasCurrentReview { discardButton }
            } else {
                Text(state.processingIndex == state.currentIndex ? "일본어를 인식하고 번역하는 중입니다." : "이 페이지가 번역되면 문구를 수정할 수 있습니다.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let failure = state.failures[state.currentIndex] {
                DisclosureGroup("처리 실패 내용") {
                    ScrollView {
                        Text(failure).font(.system(size: 11)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }.frame(maxHeight: 120)
                }.font(.system(size: 11)).foregroundStyle(.red)
            }
            if !isPending && (state.currentResult != nil || state.failures[state.currentIndex] != nil) {
                Button(state.failures[state.currentIndex] == nil ? "현재 페이지 다시 번역" : "이 페이지 재시도", systemImage: "arrow.clockwise") {
                    state.startTranslation(onlyCurrent: true, force: true)
                }.disabled(state.isBusy || state.isLoading)
            }
            Spacer(minLength: 0)
            if !state.failures.isEmpty { failureList }
            Divider()
            Button { state.chooseOutputFolder() } label: {
                Label(state.outputRoot?.lastPathComponent ?? "완성본 폴더 지정", systemImage: "folder").lineLimit(1)
            }.disabled(state.isBusy).help(state.outputRoot?.path ?? "완성본을 저장할 폴더를 선택해주세요.")
        }.font(.system(size: 12)).padding(16).background(Color(nsColor: .controlBackgroundColor))
    }
    @ViewBuilder private var reviewNotice: some View {
        if let error = state.reviewErrors[state.currentIndex] {
            Text(error).font(.system(size: 11)).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } else if state.hasCurrentReview {
            VStack(alignment: .leading, spacing: 4) {
                Label { Text("적용하지 않은 수정").fontWeight(.semibold) } icon: {
                    Image(systemName: "pencil.circle").foregroundStyle(.orange)
                }
                Text("임시 보관됨 · ‘수정 적용’을 누르면 이미지에 저장됩니다.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11))
        }
    }
    private var discardButton: some View {
        Button("수정 취소") { state.discardCurrentReview() }.disabled(state.isBusy || state.isLoading)
    }
    private func editors(_ translation: PageTranslation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(translation.blocks.indices, id: \.self) { index in
                        editor(translation.blocks[index], number: index + 1).id(translation.blocks[index].id)
                    }
                }
            }
            .onChange(of: state.blockFocusRevision) { _, _ in
                if let id = state.selectedBlockID { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .top) } }
            }
            .onChange(of: state.selectedRegionNumbers) { _, numbers in
                if let number = numbers.first, translation.blocks.indices.contains(number - 1) {
                    proxy.scrollTo(translation.blocks[number - 1].id, anchor: .top)
                }
            }
        }
    }
    private func editor(_ block: TextBlock, number: Int) -> some View {
        let active = state.isBlockSelected(block.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { state.focusBlock(block.id) } label: {
                    Text("\(number)").font(.system(size: 11, weight: .bold)).monospacedDigit()
                        .foregroundStyle(active ? Color.white : Color.secondary).frame(minWidth: 23, minHeight: 22)
                        .background(active ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain).help("이미지에서 \(number)번 문구 표시")
                Picker("문구 종류", selection: kindBinding(block)) {
                    ForEach(MangaTextKind.allCases, id: \.self) { Text($0.regionLabel).tag($0) }
                }.labelsHidden().controlSize(.small).disabled(editingDisabled)
            }
            TextField("일본어 원문", text: textBinding(block, \.originalText), axis: .vertical)
                .font(.system(size: 11)).foregroundStyle(.secondary).disabled(editingDisabled)
            if let message = MaskedTextTranslation.reviewMessage(for: block) {
                Text(message).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let interpretation = block.maskedTextInterpretation {
                VStack(alignment: .leading, spacing: 3) {
                    Text(interpretation.message).foregroundStyle(.orange)
                    if let japanese = interpretation.japanese { Text(japanese).foregroundStyle(.secondary) }
                    if let reused = interpretation.usedCachedInterpretation {
                        Text(reused ? "이전 문맥 해석 재사용" : "캐시 없이 새 문맥 판단").foregroundStyle(.secondary)
                    }
                }.font(.system(size: 10)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Button(MaskedTextTranslation.requiresContextTranslation(block.originalText) ? "Qwen으로 이 문구 다시 번역" : "이 문구 다시 번역") {
                if let draft, let index = draft.blocks.firstIndex(where: { $0.id == block.id }) {
                    state.retranslateBlock(in: draft, at: index)
                }
            }.font(.system(size: 10)).disabled(editingDisabled)
                .help("이 문구의 번역만 검수창에서 갱신합니다. ‘수정 적용’을 누르면 이미지에 저장됩니다.")
            if block.textKind == .soundEffect {
                Picker("효과음 스타일", selection: effectStyleBinding(block)) {
                    Text("전체 설정 따르기").tag("")
                    Text("원문에 맞춰 추천").tag("automatic")
                    ForEach(state.effectStyles) { Text($0.name).tag($0.id) }
                }.controlSize(.small).disabled(editingDisabled)
            }
            TextEditor(text: textBinding(block, \.translatedText)).font(.system(size: 13)).frame(minHeight: 54, maxHeight: 100)
                .padding(4).background(.background, in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).stroke(.quaternary) }
                .disabled(editingDisabled)
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
    private func textBinding(_ block: TextBlock, _ keyPath: WritableKeyPath<TextBlock, String>) -> Binding<String> {
        Binding(get: { block[keyPath: keyPath] }, set: { value in
            state.editReviewBlock(block.id) { $0[keyPath: keyPath] = value }
        })
    }
    private func kindBinding(_ block: TextBlock) -> Binding<MangaTextKind> {
        Binding(get: { block.textKind ?? .dialogue }, set: { value in
            state.editReviewBlock(block.id) { $0.textKind = value; $0.userDefinedTextKind = true }
        })
    }
    private func effectStyleBinding(_ block: TextBlock) -> Binding<String> {
        Binding(get: { block.effectStyleID ?? "" }, set: { value in
            state.editReviewBlock(block.id) { $0.effectStyleID = value.isEmpty ? nil : value }
        })
    }
    private func apply() {
        guard let draft else { return }
        do { try state.updateCurrentTranslation(draft) } catch { state.errorMessage = error.localizedDescription }
    }
}
