import AppKit
import SwiftUI

/// Window-scoped event handling; text editors and modal sheets keep their normal keys.
public struct ComicKeyboard: NSViewRepresentable {
    let handle: (NSEvent) -> Bool
    public init(handle: @escaping (NSEvent) -> Bool) { self.handle = handle }
    public func makeNSView(context: Context) -> ComicKeyboardView {
        let view = ComicKeyboardView(); view.handle = handle; return view
    }
    public func updateNSView(_ view: ComicKeyboardView, context: Context) { view.handle = handle }
    public static func dismantleNSView(_ view: ComicKeyboardView, coordinator: ()) { view.stopMonitoring() }
}

public final class ComicKeyboardView: NSView {
    var handle: ((NSEvent) -> Bool)?
    private var monitor: Any?
    public override func viewDidMoveToWindow() {
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.route(event) == nil && self != nil }
            return consumed ? nil : event
        }
    }
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    private func route(_ event: NSEvent) -> NSEvent? {
        guard let window, window.isKeyWindow, window.attachedSheet == nil, event.window == window,
              !(window.firstResponder is NSTextView), !(window.firstResponder is NSTextField),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
        return handle?(event) == true ? nil : event
    }
}
