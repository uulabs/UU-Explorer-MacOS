import Foundation

public enum BatchRenameMode: String, CaseIterable, Codable, Sendable {
    case findReplace
    case addText
    case number

    public var title: String {
        switch self {
        case .findReplace: return "Find & Replace"
        case .addText: return "Prefix / Suffix"
        case .number: return "Number"
        }
    }
}

public struct BatchRenameOptions: Sendable {
    public var mode: BatchRenameMode = .findReplace
    public var find: String = ""
    public var replace: String = ""
    public var caseSensitive: Bool = false
    public var prefix: String = ""
    public var suffix: String = ""
    public var numberBase: String = "Item"
    public var numberStart: Int = 1
    public var numberPadding: Int = 2

    public init() {}
}

public struct BatchRenameItem: Identifiable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public var id: String { url.path }

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }
}

public struct BatchRenamePreview: Identifiable, Sendable {
    public let sourceURL: URL
    public let oldName: String
    public let newName: String
    public let error: String?
    public var id: String { sourceURL.path }

    public var targetURL: URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(newName)
    }

    public var hasChange: Bool { newName != oldName }
}

public enum BatchRenamePlanner {
    public static func preview(
        items: [BatchRenameItem],
        options: BatchRenameOptions
    ) -> [BatchRenamePreview] {
        var proposed: [(item: BatchRenameItem, oldName: String, newName: String, error: String?)] = []
        for (index, item) in items.enumerated() {
            let oldName = item.url.lastPathComponent
            let result = proposedName(for: item, index: index, options: options)
            var error = result.error
            let newName = result.name

            if error == nil, newName.isEmpty {
                error = "Enter a name."
            }
            if error == nil, newName != oldName {
                if let validation = FileName.validationError(for: newName) {
                    error = validation
                }
            }
            if error == nil, newName != oldName {
                let target = item.url.deletingLastPathComponent().appendingPathComponent(newName)
                if FileManager.default.fileExists(atPath: target.path) {
                    error = "An item named “\(newName)” already exists."
                }
            }
            proposed.append((item, oldName, newName, error))
        }

        var counts: [String: Int] = [:]
        for entry in proposed where entry.error == nil && entry.newName != entry.oldName {
            counts[entry.newName.lowercased(), default: 0] += 1
        }
        var previews: [BatchRenamePreview] = []
        for entry in proposed {
            var error = entry.error
            if error == nil,
               entry.newName != entry.oldName,
               (counts[entry.newName.lowercased()] ?? 0) > 1 {
                error = "Multiple items would be renamed to “\(entry.newName)”."
            }
            previews.append(
                BatchRenamePreview(
                    sourceURL: entry.item.url,
                    oldName: entry.oldName,
                    newName: entry.newName,
                    error: error
                )
            )
        }
        return previews
    }

    private static func proposedName(
        for item: BatchRenameItem,
        index: Int,
        options: BatchRenameOptions
    ) -> (name: String, error: String?) {
        let fullName = item.url.lastPathComponent
        let ext = item.isDirectory ? "" : item.url.pathExtension
        let stem: String
        if ext.isEmpty {
            stem = fullName
        } else {
            stem = (fullName as NSString).deletingPathExtension
        }
        let extensionSuffix = ext.isEmpty ? "" : ".\(ext)"

        switch options.mode {
        case .findReplace:
            guard !options.find.isEmpty else {
                return (fullName, "Enter text to find.")
            }
            if options.caseSensitive {
                return (stem.replacingOccurrences(of: options.find, with: options.replace) + extensionSuffix, nil)
            }
            return (
                stem.replacingOccurrences(
                    of: options.find,
                    with: options.replace,
                    options: .caseInsensitive
                ) + extensionSuffix,
                nil
            )
        case .addText:
            return (options.prefix + stem + options.suffix + extensionSuffix, nil)
        case .number:
            let padding = max(1, min(options.numberPadding, 8))
            let number = options.numberStart + index
            let base = options.numberBase.isEmpty ? "Item" : options.numberBase
            let formatted = String(format: "%0\(padding)d", number)
            return ("\(base) \(formatted)\(extensionSuffix)", nil)
        }
    }
}
