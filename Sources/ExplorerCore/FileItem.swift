import Foundation

public struct FileItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let isSymbolicLink: Bool
    public let isApplication: Bool
    public let dateModified: Date?
    public let dateCreated: Date?
    public let byteSize: Int64?
    public let allocatedSize: Int64?
    public let kind: String
    public let isImage: Bool
    public let typeIdentifier: String?
    public let permissions: String?
    public let owner: String?
    public let group: String?

    public var id: String { url.path }

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        isPackage: Bool,
        isHidden: Bool,
        isSymbolicLink: Bool,
        isApplication: Bool,
        dateModified: Date?,
        dateCreated: Date? = nil,
        byteSize: Int64?,
        allocatedSize: Int64? = nil,
        kind: String,
        isImage: Bool = false,
        typeIdentifier: String? = nil,
        permissions: String? = nil,
        owner: String? = nil,
        group: String? = nil
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isSymbolicLink = isSymbolicLink
        self.isApplication = isApplication
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.byteSize = byteSize
        self.allocatedSize = allocatedSize
        self.kind = kind
        self.isImage = isImage
        self.typeIdentifier = typeIdentifier
        self.permissions = permissions
        self.owner = owner
        self.group = group
    }
}

public struct DirectoryEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isSymbolicLink: Bool

    public var id: String { url.path }

    public init(url: URL, name: String, isSymbolicLink: Bool = false) {
        self.url = url
        self.name = name
        self.isSymbolicLink = isSymbolicLink
    }
}

public struct MountPoint: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isInternal: Bool

    public var id: String { url.path }

    public init(url: URL, name: String, isInternal: Bool) {
        self.url = url
        self.name = name
        self.isInternal = isInternal
    }
}

public struct VolumeInfo: Equatable, Sendable {
    public let name: String
    public let rootURL: URL
    public let availableCapacity: Int64?
    public let totalCapacity: Int64?
    public let isInternal: Bool

    public init(
        name: String,
        rootURL: URL,
        availableCapacity: Int64?,
        totalCapacity: Int64?,
        isInternal: Bool
    ) {
        self.name = name
        self.rootURL = rootURL
        self.availableCapacity = availableCapacity
        self.totalCapacity = totalCapacity
        self.isInternal = isInternal
    }
}
