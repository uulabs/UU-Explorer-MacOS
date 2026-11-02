import Darwin
import Foundation
import UniformTypeIdentifiers

public enum FileSystemService {
    public static let listingKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .isSymbolicLinkKey,
        .isAliasFileKey,
        .contentModificationDateKey,
        .creationDateKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .typeIdentifierKey,
        .localizedNameKey
    ]

    private static let kindCache = NSCache<NSString, NSString>()

    public static func listDirectory(
        at directory: URL,
        includeHidden: Bool = false
    ) throws -> [FileItem] {
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: listingKeys,
            options: [.skipsPackageDescendants]
        )

        var result: [FileItem] = []
        result.reserveCapacity(children.count)

        for child in children {
            if child.lastPathComponent == ".nofollow" { continue }
            guard let item = fileItem(at: child, includeHidden: includeHidden) else { continue }
            result.append(item)
        }
        return result
    }

    public static func fileItem(at child: URL, includeHidden: Bool = false) -> FileItem? {
        let keys = Set(listingKeys)
        let rawName = child.lastPathComponent
        if rawName == ".nofollow" { return nil }
        let values = try? child.resourceValues(forKeys: keys)
        let isHidden = (values?.isHidden ?? false) || rawName.hasPrefix(".")
        if isHidden && !includeHidden { return nil }

        let isDirectory = values?.isDirectory ?? false
        let isPackage = values?.isPackage ?? false
        let isSymbolicLink = values?.isSymbolicLink ?? false
        let isAlias = values?.isAliasFile ?? false
        let isApplication = isDirectory && child.pathExtension.lowercased() == "app"
        let isImage = !isDirectory && (values?.typeIdentifier.flatMap { UTType($0) }?.conforms(to: .image) ?? false)

        let displayName: String
        if let localized = values?.localizedName, !localized.isEmpty {
            displayName = localized
        } else {
            displayName = rawName
        }

        let size: Int64?
        if isDirectory {
            size = nil
        } else if let fileSize = values?.fileSize {
            size = Int64(fileSize)
        } else if let allocated = values?.totalFileAllocatedSize {
            size = Int64(allocated)
        } else {
            size = nil
        }

        let kind = kindDescription(
            url: child,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isApplication: isApplication,
            isAlias: isAlias || isSymbolicLink,
            typeIdentifier: values?.typeIdentifier
        )

        var permissions: String?
        var owner: String?
        var group: String?
        var info = stat()
        if stat(child.path, &info) == 0 {
            permissions = String(format: "%03o", info.st_mode & 0o777)
            if let password = getpwuid(info.st_uid) {
                owner = String(cString: password.pointee.pw_name)
            }
            if let groupEntry = getgrgid(info.st_gid) {
                group = String(cString: groupEntry.pointee.gr_name)
            }
        }

        return FileItem(
            url: child,
            name: displayName,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isHidden: isHidden,
            isSymbolicLink: isSymbolicLink,
            isApplication: isApplication,
            dateModified: values?.contentModificationDate,
            dateCreated: values?.creationDate,
            byteSize: size,
            allocatedSize: values?.totalFileAllocatedSize.map(Int64.init),
            kind: kind,
            isImage: isImage,
            typeIdentifier: values?.typeIdentifier,
            permissions: permissions,
            owner: owner,
            group: group
        )
    }

    /// Recursively searches by display name. Package descendants are skipped and
    /// the result count is capped so a root-level search cannot run indefinitely.
    public static func recursiveSearch(
        at directory: URL,
        matching query: String,
        includeHidden: Bool = false,
        limit: Int = 2_000
    ) -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: listingKeys,
            options: options
        ) else { return [] }

        var results: [FileItem] = []
        for case let child as URL in enumerator {
            if results.count >= limit { break }
            if child.lastPathComponent == ".nofollow" { continue }
            guard let item = fileItem(at: child, includeHidden: includeHidden) else { continue }
            if item.name.localizedCaseInsensitiveContains(trimmed) {
                results.append(item)
            }
        }
        return results
    }

    /// Recursive filename search with optional size/kind/date filters.
    /// Content matching is handled by the app-level Spotlight search.
    public static func search(
        at directory: URL,
        matching query: String,
        includeHidden: Bool = false,
        filter: SearchFilter = SearchFilter(),
        limit: Int = 2_000,
        isCancelled: @escaping () -> Bool = { false },
        onProgress: ((_ scanned: Int, _ newItems: [FileItem]) -> Void)? = nil
    ) -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || filter.isActive, limit > 0 else { return [] }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: listingKeys,
            options: options
        ) else { return [] }

        var results: [FileItem] = []
        var pending: [FileItem] = []
        var scanned = 0

        for case let child as URL in enumerator {
            if scanned.isMultiple(of: 64), isCancelled() { break }
            if results.count >= limit { break }
            scanned += 1
            if child.lastPathComponent == ".nofollow" { continue }
            guard let item = fileItem(at: child, includeHidden: includeHidden) else { continue }
            if !trimmed.isEmpty && !item.name.localizedCaseInsensitiveContains(trimmed) { continue }
            guard filter.matches(item) else { continue }
            results.append(item)
            pending.append(item)

            if pending.count >= 24 || scanned.isMultiple(of: 512) {
                onProgress?(scanned, pending)
                pending.removeAll(keepingCapacity: true)
            }
        }
        onProgress?(scanned, pending)
        return results
    }

    public static func kindDescription(
        url: URL,
        isDirectory: Bool,
        isPackage: Bool,
        isApplication: Bool,
        isAlias: Bool,
        typeIdentifier: String?
    ) -> String {
        if isDirectory {
            if isApplication { return "Application" }
            if isPackage { return "Package" }
            return "Folder"
        }
        if isAlias { return "Alias" }

        let cacheKey = (typeIdentifier ?? url.pathExtension) as NSString
        if cacheKey.length > 0, let cached = kindCache.object(forKey: cacheKey) {
            return cached as String
        }

        var description: String?
        if let typeIdentifier, let type = UTType(typeIdentifier), let localized = type.localizedDescription {
            description = localized
        } else if !url.pathExtension.isEmpty,
                  let type = UTType(filenameExtension: url.pathExtension),
                  let localized = type.localizedDescription {
            description = localized
        }

        let final = description?.isEmpty == false
            ? description!
            : (url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased() + " File")
        if cacheKey.length > 0 {
            kindCache.setObject(final as NSString, forKey: cacheKey)
        }
        return final
    }

    public static func subdirectories(
        at directory: URL,
        includeHidden: Bool = false,
        limit: Int = 3000
    ) -> [DirectoryEntry] {
        Array(((try? folderChildren(at: directory, includeHidden: includeHidden)) ?? []).prefix(max(0, limit)))
    }

    /// One level only. A throwing variant lets the folder dropdown distinguish empty and unreadable folders.
    public static func folderChildren(
        at directory: URL,
        includeHidden: Bool = false
    ) throws -> [DirectoryEntry] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isHiddenKey,
            .isSymbolicLinkKey,
            .localizedNameKey
        ]
        let children = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        )

        var entries: [DirectoryEntry] = []
        for child in children {
            if child.lastPathComponent == ".nofollow" { continue }
            let values = try? child.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { continue }
            // Skip packages and symbolic links: expanding either in a tree risks loops and noise.
            if values?.isPackage == true { continue }
            if values?.isSymbolicLink == true { continue }
            let hidden = (values?.isHidden ?? false) || child.lastPathComponent.hasPrefix(".")
            if hidden && !includeHidden { continue }
            let name = values?.localizedName ?? child.lastPathComponent
            entries.append(DirectoryEntry(url: child.standardizedFileURL, name: name))
        }
        return entries.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func mountedVolumes() -> [MountPoint] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeURLKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? [URL(fileURLWithPath: "/")]

        var seen = Set<String>()
        var volumes: [MountPoint] = []

        for url in urls {
            let standardized = url.standardizedFileURL
            if standardized.path.hasPrefix("/System/Volumes") { continue }
            let values = try? standardized.resourceValues(forKeys: keys)
            if values?.volumeIsBrowsable == false { continue }
            if !seen.insert(standardized.path).inserted { continue }
            let name = values?.volumeName ?? (standardized.path == "/" ? "Macintosh HD" : standardized.lastPathComponent)
            volumes.append(
                MountPoint(
                    url: standardized,
                    name: name,
                    isInternal: values?.volumeIsInternal ?? (standardized.path == "/")
                )
            )
        }

        if !volumes.contains(where: { $0.url.path == "/" }) {
            volumes.insert(MountPoint(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isInternal: true), at: 0)
        }

        return volumes.sorted { lhs, rhs in
            if lhs.url.path == "/" { return true }
            if rhs.url.path == "/" { return false }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func volumeInfo(for url: URL) -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeIsInternalKey
        ]
        let target = url.standardizedFileURL
        guard let values = try? target.resourceValues(forKeys: keys) else { return nil }
        let root = mountedVolumes()
            .filter { PathTools.isDescendant(target, of: $0.url) }
            .max { $0.url.path.count < $1.url.path.count }?
            .url ?? URL(fileURLWithPath: "/")
        let name = values.volumeName ?? (root.path == "/" ? "Macintosh HD" : root.lastPathComponent)
        return VolumeInfo(
            name: name,
            rootURL: root,
            availableCapacity: values.volumeAvailableCapacity.map(Int64.init),
            totalCapacity: values.volumeTotalCapacity.map(Int64.init),
            isInternal: values.volumeIsInternal ?? true
        )
    }

    public static func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public static func size(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { return nil }
        guard values.isDirectory != true else { return nil }
        return values.fileSize.map(Int64.init)
    }
}
