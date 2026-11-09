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
    public static func volumeTrashURL(for volumeRoot: URL) -> URL {
        volumeRoot
            .appendingPathComponent(".Trashes", isDirectory: true)
            .appendingPathComponent(String(getuid()), isDirectory: true)
    }

    /// Deletes every item inside the current user's volume-local trash, leaving
    /// the `.Trashes/<uid>` directory itself in place. Returns the number of
    /// top-level items removed.
    @discardableResult
    public static func emptyVolumeTrash(volumeRoot: URL) throws -> Int {
        let trashDirectory = volumeTrashURL(for: volumeRoot)
        guard FileManager.default.fileExists(atPath: trashDirectory.path) else { return 0 }
        let children = try FileManager.default.contentsOfDirectory(
            at: trashDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children {
            try FileManager.default.removeItem(at: child)
        }
        return children.count
    }

    public static func permanentDelete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    @discardableResult
    public static func moveToVolumeTrash(_ url: URL, volumeRoot: URL) throws -> URL {
        let trashDirectory = volumeTrashURL(for: volumeRoot)
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
