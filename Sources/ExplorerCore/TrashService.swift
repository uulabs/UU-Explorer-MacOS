import Foundation

public enum TrashError: LocalizedError {
    case fallbackFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .fallbackFailed(let name, let reason):
            return "“\(name)” couldn’t be moved to the trash. \(reason)"
        }
    }
}

public enum TrashService {
    /// Moves an item to the system Trash. Some external volumes have no
    /// `.Trashes` directory, in which case macOS reports a permission error.
    /// Create the volume-local trash directory and move the item there instead.
    @discardableResult
    public static func recycle(_ url: URL) throws -> URL? {
        do {
            var resulting: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return resulting as URL?
        } catch {
            guard FileManager.default.fileExists(atPath: url.path),
                  let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume else {
                throw error
            }
            do {
                return try moveToVolumeTrash(url, volumeRoot: volume)
            } catch {
                throw TrashError.fallbackFailed(url.lastPathComponent, error.localizedDescription)
            }
        }
    }

    /// Fallback used when the system Trash is unavailable, usually an external
    /// volume that has never had a Trash created. The path is the same layout
    /// Finder uses: `<volume>/.Trashes/<uid>/<filename>`.
    @discardableResult
    public static func moveToVolumeTrash(_ url: URL, volumeRoot: URL) throws -> URL {
        let uid = getuid()
        let trashDirectory = volumeRoot
            .appendingPathComponent(".Trashes", isDirectory: true)
            .appendingPathComponent(String(uid), isDirectory: true)
        try FileManager.default.createDirectory(
            at: trashDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let ext = url.pathExtension
        let baseName = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let target = FileName.uniqueURL(
            in: trashDirectory,
            baseName: baseName,
            pathExtension: ext.isEmpty ? nil : ext
        )
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
