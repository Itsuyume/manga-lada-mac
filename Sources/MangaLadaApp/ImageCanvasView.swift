import AppKit
import MangaLadaCore
import SwiftUI

struct ImageCanvasView: View {
    let image: NSImage
    let blocks: [TextBlock]
    let fontScale: Double

    var body: some View {
        GeometryReader { proxy in
            let imageRect = fittedImageRect(
                imageSize: image.size,
                containerSize: proxy.size
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                ForEach(blocks) { block in
                    TranslationBubble(
                        block: block,
                        imageRect: imageRect,
                        fontScale: fontScale
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func fittedImageRect(imageSize: NSSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        let fittedSize: CGSize
        if imageAspect > containerAspect {
            let width = containerSize.width
            fittedSize = CGSize(width: width, height: width / imageAspect)
        } else {
            let height = containerSize.height
            fittedSize = CGSize(width: height * imageAspect, height: height)
        }

        return CGRect(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}

private struct TranslationBubble: View {
    let block: TextBlock
    let imageRect: CGRect
    let fontScale: Double

    var body: some View {
        let rect = overlayRect(for: block.box, imageRect: imageRect)
        Text(displayText)
            .font(.system(size: fontSize(for: rect), weight: .semibold))
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.center)
            .lineLimit(6)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(width: max(rect.width, 42), height: max(rect.height, 28))
            .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.24), lineWidth: 1)
            )
            .position(x: rect.midX, y: rect.midY)
    }

    private var displayText: String {
        let translated = block.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !translated.isEmpty {
            return translated
        }
        return block.originalText
    }

    private func overlayRect(for box: TextBox, imageRect: CGRect) -> CGRect {
        CGRect(
            x: imageRect.minX + box.x * imageRect.width,
            y: imageRect.minY + box.y * imageRect.height,
            width: box.width * imageRect.width,
            height: box.height * imageRect.height
        ).insetBy(dx: -8, dy: -5)
    }

    private func fontSize(for rect: CGRect) -> CGFloat {
        let base = min(max(rect.height * 0.32, 11), 24)
        return base * fontScale
    }
}
