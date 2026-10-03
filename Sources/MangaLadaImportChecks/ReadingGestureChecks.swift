import Foundation
import MangaLadaViewerUI

enum ReadingGestureChecks {
    @MainActor
    static func run() throws {
        let suite = "MangaLadaReadingGestureChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ReadingSettings(prefix: "reader", defaults: defaults)
        let originalLayout = settings.layout, originalDirection = settings.direction
        for invalid in [0.0, -1.0, Double.nan, Double.infinity] {
            var rejected = false
            do { try settings.updateMagnification(invalid) }
            catch ReadingGestureError.invalidMagnification { rejected = true }
            try check(rejected, "Invalid magnification was accepted.")
            try check(settings.zoom == 1, "Invalid gesture changed the zoom or began a session.")
        }
        try settings.updateMagnification(1.5)
        try settings.updateMagnification(2)
        try check(settings.zoom == 2, "Repeated pinch updates compounded instead of using the gesture's starting scale.")
        settings.endMagnification()
        try settings.updateMagnification(0.5)
        try check(settings.zoom == 1, "A new inward pinch did not shrink the previous scale.")
        settings.endMagnification()
        try settings.updateMagnification(100)
        try check(settings.zoom == 4, "Outward pinch escaped the maximum zoom.")
        try check(!settings.canZoomIn && settings.canZoomOut, "Maximum zoom did not disable only zoom-in.")
        settings.endMagnification()
        try settings.updateMagnification(0.001)
        try check(settings.zoom == 0.4, "Inward pinch escaped the minimum zoom.")
        try check(!settings.canZoomOut && settings.canZoomIn, "Minimum zoom did not disable only zoom-out.")
        settings.endMagnification()
        settings.zoom = 1
        try settings.updateMagnification(2)
        settings.endMagnification() // Cancellation and leaving the canvas end the same session.
        try settings.updateMagnification(1.25)
        try check(settings.zoom == 2.5, "Cancelled gesture left a stale starting scale.")
        settings.zoomOut()
        try settings.updateMagnification(0.5)
        try check(abs(settings.zoom - 1.15) < 0.0001, "Zoom button did not end the prior pinch session.")
        settings.endMagnification()
        settings.zoom = 1
        for _ in 0..<5 { settings.zoomIn() }
        try check(settings.zoomPercent == 200, "Repeated zoom-in displayed 199% instead of 200%.")
        for _ in 0..<6 { settings.zoomOut() }
        try check(settings.zoomPercent == 80, "Repeated zoom-out did not display the expected percentage.")
        settings.zoomOut(); settings.zoomOut()
        try check(settings.zoom == 0.4 && !settings.canZoomOut, "Button arithmetic kept zoom-out enabled at 40%.")
        for _ in 0..<18 { settings.zoomIn() }
        try check(settings.zoom == 4 && !settings.canZoomIn, "Button arithmetic did not stop at 400%.")
        try check(settings.layout == originalLayout && settings.direction == originalDirection, "Pinch zoom changed reading preferences.")
        print("Reading gesture checks passed: pinch in/out, stable per-gesture baseline, cancellation, bounds, invalid inputs, reading preferences preserved")
    }
    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure.failed(message) }
    }
    private enum CheckFailure: Error { case failed(String) }
}
