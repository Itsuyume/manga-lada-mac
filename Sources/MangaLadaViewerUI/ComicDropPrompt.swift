import SwiftUI

/// Empty-library prompt shared by both apps. Opening and dropping stay with each app's state.
public struct ComicDropPrompt: View {
    let symbol: String
    let title: String
    let message: String
    let formats: [String]
    let steps: [String]
    let openFile: () -> Void
    let openFolder: () -> Void
    public init(symbol: String, title: String, message: String, formats: [String], steps: [String] = [],
                openFile: @escaping () -> Void, openFolder: @escaping () -> Void) {
        self.symbol = symbol; self.title = title; self.message = message; self.formats = formats; self.steps = steps
        self.openFile = openFile; self.openFolder = openFolder
    }
    public var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 30, weight: .medium)).foregroundStyle(MangaUI.accentOnCanvas)
                    .frame(width: 64, height: 64)
                    .background(MangaUI.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text(title).font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                Text(message).font(.system(size: 14)).foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button(action: openFile) { Label("파일 열기", systemImage: "doc") }.buttonStyle(.borderedProminent)
                    Button(action: openFolder) { Label("폴더 열기", systemImage: "folder") }.buttonStyle(.bordered)
                }.controlSize(.large).padding(.top, 6)
                HStack(spacing: 6) {
                    ForEach(formats, id: \.self) { format in
                        Text(format).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }.padding(.top, 8)
            }
            .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 36).frame(maxWidth: 600)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            if !steps.isEmpty { stepRow }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(MangaUI.canvas)
    }
    private var stepRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 { Rectangle().fill(.white.opacity(0.2)).frame(width: 26, height: 1) }
                HStack(spacing: 7) {
                    Text("\(index + 1)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 22, height: 22).background(.white.opacity(0.12), in: Circle())
                    Text(step)
                }.font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}
