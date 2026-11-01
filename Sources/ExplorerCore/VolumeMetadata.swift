import Foundation

public struct VolumeMetadata: Equatable, Sendable {
    public let name: String
    public let format: String
    public let mountPoint: String
    public let uuid: String?
    public let totalCapacity: Int64?
    public let availableCapacity: Int64?
    public let isReadOnly: Bool
    public let isInternal: Bool
    public let isLocal: Bool
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isRootFileSystem: Bool

    public var usedCapacity: Int64? {
        guard let totalCapacity, let availableCapacity else { return nil }
        return max(0, totalCapacity - availableCapacity)
    }

    public var mediaDescription: String {
        if !isLocal { return "Network" }
        if isRemovable { return "Removable" }
        if isEjectable { return "Ejectable" }
        return isInternal ? "Internal" : "External"
    }

    public static func load(for url: URL) -> VolumeMetadata? {
        let target = url.standardizedFileURL
        guard isVolumeRoot(target) else { return nil }

        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsReadOnlyKey,
            .volumeIsInternalKey,
            .volumeIsLocalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeUUIDStringKey,
            .volumeIsRootFileSystemKey
        ]
        guard let values = try? target.resourceValues(forKeys: keys) else { return nil }
        let name = values.volumeName ?? (target.path == "/" ? "Macintosh HD" : target.lastPathComponent)
        return VolumeMetadata(
            name: name,
            format: values.volumeLocalizedFormatDescription ?? "Volume",
            mountPoint: target.path,
            uuid: values.volumeUUIDString,
            totalCapacity: values.volumeTotalCapacity.map(Int64.init),
            availableCapacity: values.volumeAvailableCapacity.map(Int64.init),
            isReadOnly: values.volumeIsReadOnly ?? false,
            isInternal: values.volumeIsInternal ?? (target.path == "/"),
            isLocal: values.volumeIsLocal ?? true,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isRootFileSystem: target.path == "/"
        )
    }

    public static func isVolumeRoot(_ url: URL) -> Bool {
        let target = url.standardizedFileURL
        let roots = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: [.skipHiddenVolumes]
        ) ?? []
        return roots.contains { $0.standardizedFileURL.path == target.path }
    }
}
