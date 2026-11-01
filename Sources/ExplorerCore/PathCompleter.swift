import Foundation

public struct PathSuggestion: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case parent
        case folder
        case file
    }

    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let kind: Kind

    public var id: String { url.path }

    public init(url: URL, name: String, isDirectory: Bool, kind: Kind? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.kind = kind ?? (isDirectory ? .folder : .file)
    }
}

public enum PathCompleter {
    /// Suggests the ancestor chain plus matching children for a partially typed path.
    public static func suggestions(
        for draft: String,
        base: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        limit: Int = 8,
        parentLimit: Int = 5
    ) -> [PathSuggestion] {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let directory: URL?
        let prefix: String

        if trimmed.contains("/") {
            if trimmed.hasSuffix("/") {
                directory = PathTools.expand(trimmed, relativeTo: base, home: home)
                prefix = ""
            } else {
                let nsPath = trimmed as NSString
                let directoryText = nsPath.deletingLastPathComponent
                prefix = nsPath.lastPathComponent
                directory = PathTools.expand(directoryText.isEmpty ? "/" : directoryText, relativeTo: base, home: home)
            }
        } else {
            directory = base
            prefix = trimmed
        }

        guard let directory, FileSystemService.directoryExists(at: directory) else { return [] }

        var parents: [PathSuggestion] = []
        var cursor = directory.standardizedFileURL
        var depth = 0
        while depth < parentLimit {
            let parent = cursor.deletingLastPathComponent().standardizedFileURL
            if parent.path == cursor.path { break }
            parents.append(
                PathSuggestion(
                    url: parent,
                    name: displayName(for: parent),
                    isDirectory: true,
                    kind: .parent
                )
            )
            cursor = parent
            depth += 1
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return parents
        }

        let loweredPrefix = prefix.lowercased()
        let showHidden = prefix.hasPrefix(".")
        var suggestions: [PathSuggestion] = []

        for child in children {
            guard suggestions.count < limit * 4 else { break }
            let name = child.lastPathComponent
            let values = try? child.resourceValues(forKeys: keys)
            let hidden = (values?.isHidden ?? false) || name.hasPrefix(".")
            if hidden && !showHidden { continue }
            if !loweredPrefix.isEmpty && !name.lowercased().hasPrefix(loweredPrefix) { continue }
            suggestions.append(
                PathSuggestion(
                    url: child.standardizedFileURL,
                    name: name,
                    isDirectory: values?.isDirectory ?? false
                )
            )
        }

        suggestions.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return parents + Array(suggestions.prefix(limit))
    }

    private static func displayName(for url: URL) -> String {
        if url.path == "/" {
            return FileSystemService.volumeInfo(for: url)?.name ?? "Macintosh HD"
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }
}
