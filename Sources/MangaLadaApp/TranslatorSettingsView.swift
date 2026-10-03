import AppKit
import MangaLadaCore
import MangaLadaRendering
import SwiftUI

struct TranslatorSettingsView: View {
    @ObservedObject var state: AppState
    @State private var configuration: LocalTranslatorConfiguration
    @State private var typography: MangaTypography
    private let fonts = ["AppleSDGothicNeo-Bold", "AppleSDGothicNeo-Heavy", "AppleSDGothicNeo-Medium", "AppleMyungjo", "NanumGothicBold", "NanumMyeongjoBold"]
        .filter { NSFont(name: $0, size: 14) != nil }
    init(state: AppState) {
        self.state = state; _configuration = State(initialValue: state.configuration); _typography = State(initialValue: state.typography)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("번역과 글자 배치").font(.system(size: 20, weight: .semibold))
            Form {
                Picker("번역 방식", selection: $configuration.provider) {
                    Text("로컬 · API 요금 없음").tag(TranslationProvider.ollama)
                    Text("Gemini Flash-Lite · 저가 API").tag(TranslationProvider.geminiFlashLite)
                }
                if configuration.provider == .ollama {
                    TextField("번역 모델", text: $configuration.ollama.model)
                    Text("기본 TranslateGemma 12B · 첫 준비 시 약 8.1GB · 이후 로컬 실행").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("로컬 모델 준비", systemImage: "arrow.down.circle") {
                        if state.saveSettings(configuration: configuration, typography: typography, renderCompleted: false) { state.prepareLocalModel() }
                    }
                } else {
                    TextField("저가 모델", text: $configuration.gemini.model)
                    SecureField("API 키", text: $configuration.gemini.apiKey)
                    Text("OCR·원문 제거·효과음 인식은 로컬입니다. 번역할 일본어 문구만 API로 전송하며 키는 Mac 키체인에 저장합니다.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider().padding(.vertical, 6)
                Toggle("효과음 추가 인식 · 느림 / 실험 단계", isOn: $configuration.enhanceSoundEffects)
                Text("기본은 검출된 말풍선·문구를 먼저 번역합니다. 복잡한 효과음과 표지는 검수가 필요합니다.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("말풍선 글꼴", selection: $typography.dialogueFontName) { ForEach(fonts, id: \.self) { Text(fontLabel($0)).tag($0) } }
                Picker("효과음 스타일", selection: effectStyleBinding) {
                    Text("원문에 맞춰 자동 추천").tag("automatic")
                    ForEach(state.effectStyles) { Text($0.name).tag($0.id) }
                    Text("글꼴 직접 선택").tag("custom")
                }
                if typography.effectStyleID == "custom" {
                    Picker("효과음 글꼴", selection: $typography.effectFontName) { ForEach(fonts, id: \.self) { Text(fontLabel($0)).tag($0) } }
                }
                HStack {
                    Text("12가지 조판 스타일 · 기본 글꼴 3개 · 추가 API 없음").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("폰트집 보기") { NSWorkspace.shared.open(SoundEffectFonts.collectionDirectory.appendingPathComponent("폰트집.html")) }
                        .disabled(!FileManager.default.fileExists(atPath: SoundEffectFonts.collectionDirectory.appendingPathComponent("폰트집.html").path))
                }
                HStack {
                    Text("글자 크기"); Slider(value: $typography.fontScale, in: 0.7...1.5)
                    Text("\(Int(typography.fontScale * 100))%").monospacedDigit().frame(width: 42)
                }
            }.formStyle(.grouped)
            HStack {
                Text("원본과 기존 번역 캐시는 유지됩니다.").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("취소") { state.showSettings = false }.keyboardShortcut(.cancelAction)
                Button("저장") { state.saveSettings(configuration: configuration, typography: typography) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(state.isBusy)
            }
        }.padding(24).frame(width: 570)
    }
    private var effectStyleBinding: Binding<String> {
        Binding(get: { typography.effectStyleID ?? "automatic" }, set: { typography.effectStyleID = $0 })
    }
    private func fontLabel(_ name: String) -> String {
        switch name {
        case "AppleSDGothicNeo-Bold": "고딕 · 굵게"
        case "AppleSDGothicNeo-Heavy": "고딕 · 아주 굵게"
        case "AppleSDGothicNeo-Medium": "고딕 · 보통"
        case "AppleMyungjo": "명조"
        default: NSFont(name: name, size: 14)?.displayName ?? name
        }
    }
}
