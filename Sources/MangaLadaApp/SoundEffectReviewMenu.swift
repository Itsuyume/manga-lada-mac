import MangaLadaCore
import SwiftUI

/// Choosing a spelling edits the existing review draft; it does not render or call a model.
struct SoundEffectReviewMenu: View {
    let options: [JapaneseSoundEffectLexicon.ReviewOption]
    let currentText: String
    let number: Int
    let choose: (String) -> Void

    var body: some View {
        if !options.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button { choose(option.korean) } label: {
                            if currentText == option.korean {
                                Label("\(option.context) · \(option.korean)", systemImage: "checkmark")
                            } else {
                                Text("\(option.context) · \(option.korean)")
                            }
                        }
                    }
                } label: { Text("뜻별 표기 선택") }
                    .controlSize(.small)
                    .accessibilityLabel("\(number)번 효과음 뜻별 표기 선택")
                    .help("선택한 한국어를 임시 수정에 보관합니다. ‘수정 적용’을 누르면 이미지에 저장됩니다.")
                Text("장면에 맞는 표현을 고르세요.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
