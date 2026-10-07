import MangaLadaCore
import SwiftUI

public struct ReadingControls: View {
    @ObservedObject var settings: ReadingSettings
    let index: Int
    let total: Int
    let navigate: (Int) -> Void
    @State private var pageNumber = ""
    @FocusState private var pageFieldFocused: Bool
    public init(settings: ReadingSettings, index: Int, total: Int, navigate: @escaping (Int) -> Void) {
        self.settings = settings; self.index = index; self.total = total; self.navigate = navigate
    }
    public var body: some View {
        HStack(spacing: 4) {
            navigationButtons
            separator
            Picker("페이지 표시", selection: $settings.layout) {
                ForEach(PageLayout.allCases, id: \.self) { Text($0.label).tag($0) }
            }.labelsHidden().fixedSize().help("페이지 표시")
            Picker("화면 맞춤", selection: $settings.fit) {
                ForEach(PageFit.allCases, id: \.self) { Text($0.label).tag($0) }
            }.labelsHidden().fixedSize().help("화면 맞춤")
            Menu {
                Picker("읽기 방향", selection: $settings.direction) {
                    ForEach(ReadingDirection.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("표지는 한 페이지로", isOn: $settings.coverAlone)
            } label: { Image(systemName: settings.direction == .rightToLeft ? "arrow.left.to.line" : "arrow.right.to.line") }
                .fixedSize().help(settings.direction.label)
            separator
            Button { settings.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                .disabled(!settings.canZoomOut).help("축소")
            Button("\(settings.zoomPercent)%") { settings.endMagnification(); settings.zoom = 1 }
                .monospacedDigit().frame(width: 50).help("확대 초기화 · 트랙패드에서 두 손가락을 벌리거나 오므려 확대·축소")
            Button { settings.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                .disabled(!settings.canZoomIn).help("확대")
        }.buttonStyle(.borderless).controlSize(.small).mangaFloatingBar()
            .onChange(of: index, initial: true) { _, value in pageNumber = total == 0 ? "0" : String(value + 1) }
            .onChange(of: total) { _, value in pageNumber = value == 0 ? "0" : String(index + 1); pageFieldFocused = false }
    }
    private var separator: some View { Divider().frame(height: 16).padding(.horizontal, 4) }
    private var navigationButtons: some View {
        HStack(spacing: 7) {
            let navigation = settings.navigation(count: total)
            let rtl = settings.direction == .rightToLeft
            Button { navigate(rtl ? navigation.next(from: index) : navigation.previous(from: index)) } label: { Image(systemName: "chevron.left") }
                .disabled(total == 0 || (rtl ? navigation.next(from: index) : navigation.previous(from: index)) == index).help(rtl ? "다음 페이지" : "이전 페이지")
            TextField("페이지", text: $pageNumber).textFieldStyle(.roundedBorder).frame(width: 44)
                .focused($pageFieldFocused)
                .multilineTextAlignment(.center).onSubmit(jump).accessibilityLabel("이동할 페이지 번호")
            Text("/ \(total)").monospacedDigit().foregroundStyle(.secondary)
            Button { navigate(rtl ? navigation.previous(from: index) : navigation.next(from: index)) } label: { Image(systemName: "chevron.right") }
                .disabled(total == 0 || (rtl ? navigation.previous(from: index) : navigation.next(from: index)) == index).help(rtl ? "이전 페이지" : "다음 페이지")
        }
    }
    private func jump() {
        guard let number = Int(pageNumber), (1...max(1, total)).contains(number), total > 0 else {
            pageNumber = total == 0 ? "0" : String(index + 1); return
        }
        navigate(number - 1)
        pageFieldFocused = false
    }
}
