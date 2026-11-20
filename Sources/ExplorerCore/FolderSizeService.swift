import Foundation

public struct FolderSize: Equatable, Sendable {
    public let bytes: Int64
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let directoryCount: Int

    public init(bytes: Int64, allocatedBytes: Int64, fileCount: Int, directoryCount: Int) {
        self.bytes = bytes
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.directoryCount = directoryCount
    }
}

public enum FolderSizeService {
    /// Sums regular file sizes recursively. Symbolic links are skipped so a
    /// folder scan cannot loop or charge the same external data twice.
    public static func calculate(
        at directory: URL,
        shouldCancel: () -> Bool = { false }
    ) -> FolderSize {
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isRegularFileKey
        ]
        let keySet = Set(keys)
        var bytes: Int64 = 0
        var allocated: Int64 = 0
        var files = 0
        var directories = 0

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return FolderSize(bytes: 0, allocatedBytes: 0, fileCount: 0, directoryCount: 0)
        }

        var reachedEnd = false
        while !reachedEnd && !shouldCancel() {
            autoreleasepool {
                for _ in 0..<128 {
                    if shouldCancel() {
                        reachedEnd = true
                        break
                    }
                    guard let child = enumerator.nextObject() as? URL else {
                        reachedEnd = true
                        break
                    }
                    guard let values = try? child.resourceValues(forKeys: keySet) else { continue }
                    if values.isSymbolicLink == true { continue }
                    if values.isDirectory == true {
                        directories += 1
                        continue
                    }
                    guard values.isRegularFile == true else { continue }
                    files += 1
                    let size = Int64(values.fileSize ?? 0)
                    bytes += size
                    allocated += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                }
            }
        }

        return FolderSize(
            bytes: bytes,
            allocatedBytes: allocated,
            fileCount: files,
            directoryCount: directories
        )
    }
}
