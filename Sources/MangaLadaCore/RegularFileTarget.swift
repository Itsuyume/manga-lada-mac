import Foundation

/// Missing output files are valid; directories, links and other file types are not.
public enum RegularFileTarget {
    public static func exists(at url: URL) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure.notRegularFile(url) }
            return true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return false
        }
    }

    public enum Failure: LocalizedError {
        case notRegularFile(URL)
        public var errorDescription: String? {
            switch self { case .notRegularFile(let url): "저장 위치가 일반 파일이 아닙니다: \(url.lastPathComponent)" }
        }
    }
}
