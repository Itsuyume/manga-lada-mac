import MangaLadaCore
import SwiftUI

extension AppState {
    /// All review controls read live state and reject callbacks from a removed page/session.
    func reviewBinding<Value>(_ block: TextBlock, value: @escaping (TextBlock) -> Value,
                              change: @escaping (inout TextBlock, Value) -> Void,
                              previewsLettering: Bool = false) -> Binding<Value> {
        let page = currentIndex, session = sessionID
        return Binding(get: {
            guard self.currentIndex == page, self.sessionID == session,
                  let current = self.currentReview?.blocks.first(where: { $0.id == block.id }) else {
                // SwiftUI can read a removed control once more during teardown.
                return value(block)
            }
            return value(current)
        }, set: { newValue in
            guard self.currentIndex == page, self.sessionID == session else { return }
            self.editReviewBlock(block.id) { change(&$0, newValue) }
            if previewsLettering { self.scheduleLetteringPreview() }
        })
    }
}
