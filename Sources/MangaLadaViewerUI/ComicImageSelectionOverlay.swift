import MangaLadaCore
import SwiftUI

struct ComicImageSelectionOverlay: View {
    @Binding var selection: TextBox?
    let size: CGSize
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            if let box = selection {
                Rectangle().fill(MangaUI.accent.opacity(0.12))
                    .overlay { Rectangle().stroke(MangaUI.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 3])) }
                    .frame(width: size.width * box.width, height: size.height * box.height)
                    .offset(x: size.width * box.x, y: size.height * box.y).allowsHitTesting(false)
            }
        }.frame(width: size.width, height: size.height)
            .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                selection = ImageRegionSelection.box(from: value.startLocation, to: value.location, in: size)
            }.onEnded { value in
                selection = ImageRegionSelection.box(from: value.startLocation, to: value.location, in: size)
            })
            .accessibilityLabel("이미지에서 번역할 영역을 드래그로 지정")
    }
}
