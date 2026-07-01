import MangaLadaCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()
            ViewerSurface()
            FooterBar()
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(KeyCaptureView(handle: handleKeyPress).frame(width: 0, height: 0))
        .alert(
            "작업 실패",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private func handleKeyPress(_ event: NSEvent) {
        switch event.keyCode {
        case 49:
            Task { await appState.translateCurrentPage(force: false) }
        case 123:
            appState.goToPreviousPage()
        case 124:
            appState.goToNextPage()
        default:
            break
        }
    }
}

private struct HeaderBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Text("Manga Lada")
                .font(.system(size: 15, weight: .semibold))

            Text(appState.pageLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 64)

            Divider().frame(height: 22)

            Button {
                Task { await appState.openImageFromPanel() }
            } label: {
                Label("이미지 열기", systemImage: "photo")
            }

            Button {
                Task { await appState.openFolderFromPanel() }
            } label: {
                Label("폴더 열기", systemImage: "folder")
            }

            Button {
                appState.goToPreviousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(appState.currentIndex == 0)
            .help("이전 페이지")

            Button {
                appState.goToNextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(appState.currentIndex + 1 >= appState.pages.count)
            .help("다음 페이지")

            Button {
                Task { await appState.translateCurrentPage(force: false) }
            } label: {
                Label(appState.isBusy ? "처리 중" : "번역", systemImage: "captions.bubble")
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.currentPage == nil || appState.isBusy)

            Button {
                Task { await appState.clearCurrentCacheAndRetranslate() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .disabled(appState.currentPage == nil || appState.isBusy)
            .help("캐시 삭제 후 다시 번역")

            Spacer(minLength: 12)

            Toggle("자동", isOn: $appState.autoTranslate)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("페이지를 열 때 캐시 또는 번역을 자동 실행")

            HStack(spacing: 6) {
                Image(systemName: "textformat.size")
                    .foregroundStyle(.secondary)
                Slider(value: $appState.overlayFontScale, in: 0.75...1.8)
                    .frame(width: 120)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .buttonStyle(.bordered)
    }
}

private struct ViewerSurface: View {
    @EnvironmentObject private var appState: AppState
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            if let image = appState.currentImage {
                ImageCanvasView(
                    image: image,
                    blocks: appState.mode == .translated ? appState.translation?.blocks ?? [] : [],
                    fontScale: appState.overlayFontScale
                )
                .padding(18)
            } else {
                EmptyStateView()
            }

            if appState.isBusy {
                ProgressOverlay(message: appState.statusMessage)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(14)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else {
                return false
            }

            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    Task { @MainActor in
                        appState.errorMessage = "드롭한 항목을 읽지 못했습니다. \(error.localizedDescription)"
                    }
                    return
                }

                guard let url = droppedFileURL(from: item) else {
                    Task { @MainActor in
                        appState.errorMessage = "드롭한 항목이 파일 URL이 아닙니다."
                    }
                    return
                }

                Task { @MainActor in
                    await appState.openDroppedURL(url)
                }
            }

            return true
        }
    }
}

private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }

    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }

    if let string = item as? String {
        return URL(string: string)
    }

    return nil
}

private struct FooterBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(appState.isBusy ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            Text(appState.statusMessage)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Space: 번역   ←/→: 페이지 이동   ⌘O: 열기")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("이미지나 폴더를 열면 바로 볼 수 있습니다.")
                .font(.system(size: 17, weight: .semibold))

            Text("스페이스바로 OCR과 번역을 실행합니다.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(28)
    }
}

private struct ProgressOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 16, y: 8)
    }
}
