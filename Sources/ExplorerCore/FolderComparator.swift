import Foundation

public enum FolderDifferenceState: String, Equatable, Sendable {
    case leftOnly
    case rightOnly
    case different
    case identical
}

public struct FolderDifference: Identifiable, Sendable {
    public let name: String
    public let left: FileItem?
    public let right: FileItem?
    public let state: FolderDifferenceState

    public var id: String { name }
    public var isDifference: Bool { state != .identical }

    public init(name: String, left: FileItem?, right: FileItem?, state: FolderDifferenceState) {
        self.name = name
        self.left = left
        self.right = right
        self.state = state
    }
}

public enum FolderComparator {
    /// Compares immediate children by name. Directories are considered equal
    /// when present on both sides; files are equal when size and modification
    /// date match. The user can still choose to copy any row explicitly.
    public static func compare(left: [FileItem], right: [FileItem]) -> [FolderDifference] {
        let leftByName = Dictionary(grouping: left, by: { $0.name.lowercased() }).compactMapValues(\.first)
        let rightByName = Dictionary(grouping: right, by: { $0.name.lowercased() }).compactMapValues(\.first)
        let names = Set(leftByName.keys).union(rightByName.keys)

        return names.map { key in
            let leftItem = leftByName[key]
            let rightItem = rightByName[key]
            let displayName = leftItem?.name ?? rightItem?.name ?? key
            if let leftItem, let rightItem {
                let same: Bool
                if leftItem.isDirectory || rightItem.isDirectory {
                    same = leftItem.isDirectory && rightItem.isDirectory
                } else {
                    same = leftItem.byteSize == rightItem.byteSize
                        && leftItem.dateModified == rightItem.dateModified
                }
                return FolderDifference(
                    name: displayName,
                    left: leftItem,
                    right: rightItem,
                    state: same ? .identical : .different
                )
            } else if let leftItem {
                return FolderDifference(name: displayName, left: leftItem, right: nil, state: .leftOnly)
            } else {
                return FolderDifference(name: displayName, left: nil, right: rightItem, state: .rightOnly)
            }
        }
        .sorted { lhs, rhs in
            if lhs.isDifference != rhs.isDifference { return lhs.isDifference }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
