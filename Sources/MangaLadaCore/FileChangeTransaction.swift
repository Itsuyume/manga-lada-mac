import Foundation

/// Restores these files if a serialized, synchronous save reports an error.
/// This is not a crash-recovery journal; callers own serialization of the target paths.
public enum FileChangeTransaction {
    public static func withRollback<Value>(at urls: [URL], _ action: () throws -> Value) throws -> Value {
        var seen: Set<URL> = []
        let targets = urls.map(\.standardizedFileURL).filter { seen.insert($0).inserted }
        let snapshots = try targets.map(Snapshot.init)
        do { return try action() }
        catch {
            let original = error
            var restorationErrors: [String] = []
            for snapshot in snapshots.reversed() {
                do { try snapshot.restore() }
                catch { restorationErrors.append("\(snapshot.url.lastPathComponent): \(error.localizedDescription)") }
            }
            guard restorationErrors.isEmpty else {
                throw RestorationFailure(original: original, details: restorationErrors)
            }
            throw original
        }
    }

    private struct Snapshot {
        let url: URL
        let contents: Data?

        init(_ url: URL) throws {
            self.url = url
            contents = try RegularFileTarget.exists(at: url) ? Data(contentsOf: url, options: .mappedIfSafe) : nil
        }

        func restore() throws {
            if let contents { try contents.write(to: url, options: .atomic); return }
            guard try RegularFileTarget.exists(at: url) else { return }
            try FileManager.default.removeItem(at: url)
        }
    }

    private struct RestorationFailure: LocalizedError {
        let original: any Error
        let details: [String]
        var errorDescription: String? {
            "저장 실패: \(original.localizedDescription) 기존 파일 복원도 실패했습니다: \(details.joined(separator: "; "))"
        }
    }
}
