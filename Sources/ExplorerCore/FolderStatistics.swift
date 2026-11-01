import Foundation
import Darwin

/// Metadata-only totals. Never follows symbolic links or reads file contents.
public struct FolderStatistics: Sendable {
    public var logicalBytes: Int64 = 0
    public var allocatedBytes: Int64 = 0
    public var fileCount = 0
    public var folderCount = 0
    public var symbolicLinkCount = 0
    public var inaccessibleCount = 0
    public var isComplete = false
    public var isCancelled = false

    public init() {}

    public static func calculate(
        at root: URL,
        isCancelled: @escaping () -> Bool = { false },
        progress: (FolderStatistics) -> Void = { _ in }
    ) -> FolderStatistics {
        var result = FolderStatistics()
        var allocatedIdentities = Set<String>()
        var lastUpdate = Date.distantPast

        func add(_ url: URL, isRoot: Bool = false) -> Bool {
            var metadata = stat()
            guard url.withUnsafeFileSystemRepresentation({ path in
                path.map { lstat($0, &metadata) } ?? -1
            }) == 0 else {
                result.inaccessibleCount += 1
                return false
            }
            let kind = metadata.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFDIR) {
                if !isRoot { result.folderCount += 1 }
                return true
            }
            result.fileCount += 1
            if kind == mode_t(S_IFLNK) { result.symbolicLinkCount += 1 }
            result.logicalBytes += max(0, metadata.st_size)
            let identity = "\(metadata.st_dev):\(metadata.st_ino)"
            if metadata.st_nlink <= 1 || allocatedIdentities.insert(identity).inserted {
                result.allocatedBytes += max(0, Int64(metadata.st_blocks) * 512)
            }
            return false
        }

        if isCancelled() {
            result.isCancelled = true
            return result
        }
        let isDirectory = add(root, isRoot: true)
        if isDirectory {
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [],
                errorHandler: { _, _ in
                    result.inaccessibleCount += 1
                    return !isCancelled()
                }
            )
            if let enumerator {
                while !isCancelled(), let url = enumerator.nextObject() as? URL {
                    _ = add(url)
                    if Date().timeIntervalSince(lastUpdate) >= 0.2 {
                        progress(result)
                        lastUpdate = Date()
                    }
                }
            } else {
                result.inaccessibleCount += 1
            }
        }
        result.isCancelled = isCancelled()
        result.isComplete = !result.isCancelled
        return result
    }
}
