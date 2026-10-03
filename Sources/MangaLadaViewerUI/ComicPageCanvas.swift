import AppKit
import MangaLadaCore
import SwiftUI

public struct ComicPageCanvas: View {
    let pages: [URL]
    let index: Int
    @ObservedObject var settings: ReadingSettings
    let revision: Int
    let onSelect: (Int) -> Void
    let selection: Binding<TextBox?>?
    let regions: [TextBlock]
    let selectedRegionID: Binding<UUID?>?
    @State private var scrollPage: Int?
    @GestureState private var isMagnifying = false
    public init(pages: [URL], index: Int, settings: ReadingSettings, revision: Int = 0, selection: Binding<TextBox?>? = nil,
                regions: [TextBlock] = [], selectedRegionID: Binding<UUID?>? = nil, onSelect: @escaping (Int) -> Void) {
        self.pages = pages; self.index = index; self.settings = settings; self.revision = revision; self.selection = selection; self.onSelect = onSelect
        self.regions = regions; self.selectedRegionID = selectedRegionID
    }
    public var body: some View {
        GeometryReader { geometry in
            if settings.layout == .continuous && selection == nil {
                continuous(in: geometry.size)
            } else {
                let indices = selection == nil ? settings.navigation(count: pages.count).displayedPages(at: index) : [index]
                ScrollView([.horizontal, .vertical]) {
                    HStack(spacing: 4) {
                        ForEach(indices, id: \.self) { number in
                            ComicPageImage(url: pages[number], maximumSize: pageSize(geometry.size, count: indices.count),
                                           fitWidth: settings.fit == .width, zoom: settings.zoom, revision: revision, selection: selection,
                                           regions: number == index ? regions : [], selectedRegionID: selectedRegionID)
                        }
                    }.padding(20).frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }.id("\(index)-\(settings.layout.rawValue)")
            }
        }.background(MangaUI.canvas)
            .simultaneousGesture(MagnificationGesture()
                .updating($isMagnifying) { _, active, _ in active = true }
                .onChanged { factor in
                    do { try settings.updateMagnification(Double(factor)) }
                    catch { settings.endMagnification(); NSLog("Manga reader magnification: %@", error.localizedDescription); NSSound.beep() }
                }
                .onEnded { _ in settings.endMagnification() })
            .onChange(of: isMagnifying) { _, active in if !active { settings.endMagnification() } }
            .onDisappear { settings.endMagnification() }
    }
    private func pageSize(_ size: CGSize, count: Int) -> CGSize {
        CGSize(width: max(1, (size.width - 40 - Double(max(0, count - 1)) * 4) / Double(max(1, count))),
               height: max(1, size.height - 40))
    }
    private func continuous(in size: CGSize) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(pages.indices, id: \.self) { number in
                    ComicPageImage(url: pages[number], maximumSize: pageSize(size, count: 1),
                                   fitWidth: true, zoom: settings.zoom, revision: revision,
                                   regions: number == index ? regions : [], selectedRegionID: selectedRegionID)
                        .id(number).onTapGesture { onSelect(number) }
                }
            }.scrollTargetLayout().padding(20)
        }
        .scrollPosition(id: $scrollPage, anchor: .top)
        .onAppear { scrollPage = index }
        .onChange(of: index) { _, value in if value != scrollPage { scrollPage = value } }
        .onChange(of: scrollPage) { _, value in if let value, value != index { onSelect(value) } }
    }
}
