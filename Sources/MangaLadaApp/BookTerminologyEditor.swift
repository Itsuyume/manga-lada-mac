import Foundation
import MangaLadaCore
import SwiftUI

struct BookTerminologyEditor: View {
    @ObservedObject var state: AppState
    @State private var source = ""
    @State private var korean = ""
    private var editingDisabled: Bool { state.isBusy || state.isLoading || state.sourceURL == nil }
    var body: some View {
        DisclosureGroup(state.terminologyReadError == nil ? "책 용어집 · \(state.bookTerminology.entries.count)개" : "책 용어집 · 읽기 오류") {
            VStack(alignment: .leading, spacing: 8) {
                if let failure = state.terminologyReadError {
                    Text(failure).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("파일 보기") { state.revealBookTerminology() }
                        Button("다시 읽기") { state.reloadBookTerminology() }
                    }.disabled(editingDisabled)
                } else {
                    fields
                    if !state.bookTerminology.entries.isEmpty { entries }
                    Text("새 번역과 문구 재번역부터 사용합니다. 저장된 이미지와 임시 수정은 유지됩니다.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.top, 8)
        }.font(.system(size: 11))
    }
    private var fields: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                TextField("원문", text: $source).accessibilityLabel("책 용어집 원문")
                TextField("한국어 표기", text: $korean).accessibilityLabel("책 용어집 한국어 표기")
            }.textFieldStyle(.roundedBorder)
            Button("추가·변경") {
                if state.setBookTerm(source: source, korean: korean) { source = ""; korean = "" }
            }.disabled(source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || korean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(editingDisabled)
    }
    private var entries: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(state.bookTerminology.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.source).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.korean).frame(maxWidth: .infinity, alignment: .leading)
                        Button { state.removeBookTerm(source: entry.source) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).accessibilityLabel("\(entry.source) 용어 삭제")
                    }.textSelection(.enabled)
                }
            }
        }.frame(maxHeight: 100).disabled(editingDisabled)
    }
}
