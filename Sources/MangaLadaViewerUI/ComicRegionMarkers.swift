import MangaLadaCore
import SwiftUI

struct ComicRegionMarkers: View {
    let blocks: [TextBlock]
    let size: CGSize
    let selectedID: Binding<UUID?>?
    let selection: TextBox?
    var onMove: ((UUID, CGSize) -> Void)?
    let useLetteringCoordinates: Bool
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                ComicRegionMarker(block: block, number: index + 1, size: size, selectedID: selectedID, selection: selection,
                                  onMove: onMove, useLetteringCoordinates: useLetteringCoordinates)
            }
        }.frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

private struct ComicRegionMarker: View {
    let block: TextBlock
    let number: Int
    let size: CGSize
    let selectedID: Binding<UUID?>?
    let selection: TextBox?
    let onMove: ((UUID, CGSize) -> Void)?
    let useLetteringCoordinates: Bool
    @GestureState private var displacement = CGSize.zero

    var body: some View {
        let bounds = useLetteringCoordinates ? LetteringPreferences.displayBounds(for: block) : block.userDefinedBounds ?? block.box
        let kind = block.textKind ?? .dialogue
        let active = selectedID?.wrappedValue == block.id || (selection.map { ImageRegionSelection.containsCenter($0, of: block.box) } ?? false)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(.white.opacity(0.001))
                .frame(width: size.width * bounds.width, height: size.height * bounds.height)
                .overlay { Rectangle().stroke(kind.regionColor.opacity(active ? 1 : 0.5), lineWidth: active ? 2 : 1) }
                .contentShape(Rectangle()).onTapGesture { selectedID?.wrappedValue = block.id }
                // The marker moves during dragging, so measure in a fixed coordinate space.
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .updating($displacement) { value, offset, _ in offset = value.translation }
                    .onChanged { _ in if selectedID?.wrappedValue != block.id { selectedID?.wrappedValue = block.id } }
                    .onEnded { value in
                        onMove?(block.id, CGSize(width: value.translation.width / size.width, height: value.translation.height / size.height))
                    }, including: onMove == nil ? .none : .all)
                .allowsHitTesting(onMove != nil)
                .help("클릭하여 선택 · 드래그하여 글자 이동 · 수정 적용으로 저장")
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
            .offset(x: size.width * bounds.x + displacement.width, y: size.height * bounds.y + displacement.height)
    }
}
