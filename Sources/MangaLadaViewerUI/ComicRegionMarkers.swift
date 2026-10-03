import MangaLadaCore
import SwiftUI

struct ComicRegionMarkers: View {
    let blocks: [TextBlock]
    let size: CGSize
    let selectedID: Binding<UUID?>?
    let selection: TextBox?
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                marker(block, number: index + 1)
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }
    private func marker(_ block: TextBlock, number: Int) -> some View {
        let bounds = block.userDefinedBounds ?? block.balloonShape?.bounds ?? block.box
        let kind = block.textKind ?? .dialogue
        let active = selectedID?.wrappedValue == block.id || (selection.map { ImageRegionSelection.containsCenter($0, of: block.box) } ?? false)
        return ZStack(alignment: .topLeading) {
            Rectangle().stroke(kind.regionColor.opacity(active ? 1 : 0.5), lineWidth: active ? 2 : 1).allowsHitTesting(false)
            Button { selectedID?.wrappedValue = block.id } label: {
                Text("\(number) \(kind.regionBadge)").font(.system(size: 10, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 3)
                    .background(active ? kind.regionColor : Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(kind.regionColor, lineWidth: 1) }
                    .fixedSize(horizontal: true, vertical: true)
            }.buttonStyle(.plain).help("\(number)번 \(kind.regionLabel) · \(block.originalText)")
                .accessibilityLabel("\(number)번 \(kind.regionLabel) 선택")
                .offset(y: max(-20, -size.height * bounds.y))
        }.frame(width: size.width * bounds.width, height: size.height * bounds.height, alignment: .topLeading)
            .offset(x: size.width * bounds.x, y: size.height * bounds.y)
    }
}
