import Foundation

public struct Breadcrumb: Identifiable, Hashable, Sendable {
    public let name: String
    public let path: String

    public var id: String { path }

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public enum PathTools {
    /// Expands a user-typed path. Supports absolute paths, `~`, `~/…`, and relative paths.
    public static func expand(
        _ raw: String,
        relativeTo base: URL? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text == "~" {
            return home.standardizedFileURL
        }
        if text.hasPrefix("~/") {
            text = home.path + String(text.dropFirst(1))
        }
        if text.hasPrefix("/") {
            return URL(fileURLWithPath: text).standardizedFileURL
        }
        guard let base else { return nil }
        return base.appendingPathComponent(text).standardizedFileURL
    }

    public static func isDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let ancestorPath = ancestor.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        if ancestorPath == "/" { return candidatePath.hasPrefix("/") }
        return candidatePath == ancestorPath || candidatePath.hasPrefix(ancestorPath + "/")
    }

    public static func parent(of url: URL) -> URL? {
        let standardized = url.standardizedFileURL
        guard standardized.path != "/" else { return nil }
        return standardized.deletingLastPathComponent()
    }

    /// Breadcrumbs for the path bar. The first crumb represents the containing volume.
    public static func breadcrumbs(
        for url: URL,
        volumeRoot: URL? = nil,
        volumeName: String = "Macintosh HD"
    ) -> [Breadcrumb] {
        let target = url.standardizedFileURL
        var root = (volumeRoot ?? URL(fileURLWithPath: "/")).standardizedFileURL
        if !isDescendant(target, of: root) {
            root = URL(fileURLWithPath: "/")
        }

        let rootPath = root.path
        var result = [Breadcrumb(name: volumeName, path: rootPath)]
        guard target.path != rootPath else { return result }

        let relative: String
        if rootPath == "/" {
            relative = String(target.path.dropFirst())
        } else {
            relative = String(target.path.dropFirst(rootPath.count + 1))
        }

        var accumulated = rootPath
        for component in relative.split(separator: "/") where !component.isEmpty {
            if accumulated == "/" {
                accumulated = "/" + component
            } else {
                accumulated += "/" + component
            }
            result.append(Breadcrumb(name: String(component), path: accumulated))
        }
        return result
    }

    public static func abbreviateHome(
        _ path: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let homePath = home.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }
}
