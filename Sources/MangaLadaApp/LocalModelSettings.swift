import MangaLadaCore
import SwiftUI

struct LocalModelSettings: View {
    @Binding private var model: String
    @Binding private var retention: OllamaConfiguration.Retention
    @State private var selection: Preset
    @State private var customModel: String
    let prepare: () -> Void

    init(model: Binding<String>, retention: Binding<OllamaConfiguration.Retention>, prepare: @escaping () -> Void) {
        _model = model; _retention = retention; self.prepare = prepare
        _selection = State(initialValue: Preset.allCases.first { $0.modelName == model.wrappedValue } ?? .custom)
        _customModel = State(initialValue: model.wrappedValue)
    }
    var body: some View {
        Picker("로컬 모델", selection: Binding(get: { selection }, set: { select($0) })) {
            ForEach(Preset.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        if selection == .custom {
            TextField("모델 이름", text: $model)
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(selection.detail).fixedSize(horizontal: false, vertical: true)
            Text(selection.storage).fixedSize(horizontal: false, vertical: true)
            Button("로컬 모델 준비", systemImage: "arrow.down.circle", action: prepare)
                .font(.system(size: 12)).foregroundStyle(.primary)
                .disabled(model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.font(.system(size: 11)).foregroundStyle(.secondary)
        Picker("번역 모델 대기", selection: $retention) {
            ForEach(OllamaConfiguration.Retention.allCases, id: \.self) { Text(retentionLabel($0)).tag($0) }
        }
        Text("마지막 번역 후 이 시간이 지나면 모델 메모리를 비웁니다. 다음 번역은 모델을 다시 읽느라 조금 늦게 시작할 수 있습니다. 변경은 다음 번역부터 적용되며 모델 파일은 유지됩니다.")
            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func retentionLabel(_ value: OllamaConfiguration.Retention) -> String {
        switch value {
        case .short: "1분 · 메모리 절약"
        case .balanced: "5분 · 균형"
        case .extended: "15분 · 연속 작업"
        }
    }
    private func select(_ preset: Preset) {
        if selection == .custom { customModel = model }
        selection = preset
        model = preset.modelName ?? customModel
    }
    private enum Preset: CaseIterable {
        case translation, context, custom
        var modelName: String? {
            switch self {
            case .translation: OllamaConfiguration.defaultModel
            case .context: OllamaConfiguration.visionModel
            case .custom: nil
            }
        }
        var label: String {
            switch self {
            case .translation: "TranslateGemma 12B · 번역 전용"
            case .context: "Qwen 3.5 9B · 문맥·종류 분류"
            case .custom: "모델 이름 직접 입력"
            }
        }
        var detail: String {
            switch self {
            case .translation: "일본어 문구를 한국어로 번역합니다. 대사·효과음의 종류는 인식 결과 또는 직접 지정한 값을 따릅니다."
            case .context: "앞 페이지 문맥을 참고하고 대사·설명·효과음 종류를 함께 판단합니다. 문맥과 효과음 번역은 검수가 필요합니다."
            case .custom: "Ollama에 설치할 모델 이름을 입력하세요. 로컬 모델만 사용할 수 있습니다."
            }
        }
        var storage: String {
            switch self {
            case .translation: "모델 파일 약 8.1GB · 첫 준비 뒤 로컬 실행"
            case .context: "모델 파일 약 6.6GB · 첫 준비 뒤 로컬 실행"
            case .custom: "필요한 저장 공간과 속도는 모델에 따라 달라집니다."
            }
        }
    }
}
