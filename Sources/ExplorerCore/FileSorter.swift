import Foundation

public enum SortField: String, CaseIterable, Codable, Sendable {
    case name
    case dateModified
    case dateCreated
    case kind
    case size
    case sizeOnDisk
    case permissions
    case owner

    public var title: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        case .kind: return "Type"
        case .size: return "Size"
        case .sizeOnDisk: return "Size on Disk"
        case .permissions: return "Permissions"
        case .owner: return "Owner"
        }
    }
}

public enum FileSorter {
    /// Windows Explorer ordering: folders always come first, then the chosen sort field,
    /// with natural (localized numeric-aware) name ordering as the tiebreaker.
    public static func sorted(_ items: [FileItem], by field: SortField, ascending: Bool) -> [FileItem] {
        items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }

            switch field {
            case .name:
                break
            case .kind:
                let result = lhs.kind.localizedStandardCompare(rhs.kind)
                if result != .orderedSame {
                    return ascending ? result == .orderedAscending : result == .orderedDescending
                }
            case .size:
                if let result = optionalOrder(lhs.byteSize, rhs.byteSize, ascending: ascending) {
                    return result
                }
            case .sizeOnDisk:
                if let result = optionalOrder(lhs.allocatedSize, rhs.allocatedSize, ascending: ascending) {
                    return result
                }
            case .dateModified:
                if let result = optionalOrder(lhs.dateModified, rhs.dateModified, ascending: ascending) {
                    return result
                }
            case .dateCreated:
                if let result = optionalOrder(lhs.dateCreated, rhs.dateCreated, ascending: ascending) {
                    return result
                }
            case .permissions:
                let result = (lhs.permissions ?? "").localizedStandardCompare(rhs.permissions ?? "")
                if result != .orderedSame {
                    return ascending ? result == .orderedAscending : result == .orderedDescending
                }
            case .owner:
                let result = (lhs.owner ?? "").localizedCompare(rhs.owner ?? "")
                if result != .orderedSame {
                    return ascending ? result == .orderedAscending : result == .orderedDescending
                }
            }

            let nameResult = lhs.name.localizedStandardCompare(rhs.name)
            if nameResult != .orderedSame {
                return ascending ? nameResult == .orderedAscending : nameResult == .orderedDescending
            }
            return lhs.url.path < rhs.url.path
        }
    }

    /// Returns nil when values tie. Missing values always sort last, even when descending.
    private static func optionalOrder<T: Comparable>(_ lhs: T?, _ rhs: T?, ascending: Bool) -> Bool? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case (nil, _):
            return false
        case (_, nil):
            return true
        case let (left?, right?):
            if left == right { return nil }
            return ascending ? left < right : left > right
        }
    }
}
