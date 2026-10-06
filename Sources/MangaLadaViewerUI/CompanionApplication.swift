import AppKit
import MangaLadaCore

public enum CompanionApplication {
    case translator, reader

    /// The companion of this edition, never the original app of the same role.
    var name: String { self == .translator ? MangaLadaEdition.translatorName : MangaLadaEdition.readerName }

    @MainActor
    public func open(_ document: URL) async throws {
        let candidates = [Bundle.main.bundleURL.deletingLastPathComponent(),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                          URL(fileURLWithPath: "/Applications", isDirectory: true)]
        guard let application = candidates.map({ $0.appendingPathComponent(name + ".app") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw CompanionApplicationError.notInstalled(name)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([document], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

private enum CompanionApplicationError: LocalizedError {
    case notInstalled(String)
    var errorDescription: String? {
        switch self {
        case .notInstalled(let name): "\(name) 앱을 함께 설치해주세요."
        }
    }
}
