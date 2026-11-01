import Foundation

public enum FileName {
    /// Returns a user-facing validation message, or nil when the name is usable.
    public static func validationError(for rawName: String) -> String? {
        if rawName.isEmpty { return "Enter a name." }
        if rawName == "." || rawName == ".." { return "That name is reserved." }
        if rawName.contains("/") { return "A name can't contain “/”." }
        if rawName.contains(":") { return "A name can't contain “:”." }
        if rawName.contains("\0") { return "A name can't contain a null character." }
        if rawName != rawName.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "A name can't begin or end with a space."
        }
        if rawName.utf8.count > 255 { return "That name is too long." }
        return nil
    }

    /// Returns a path that does not exist yet, adding " 2", " 3", … as needed.
    public static func uniqueURL(
        in directory: URL,
        baseName: String,
        pathExtension: String? = nil
    ) -> URL {
        let suffix = (pathExtension?.isEmpty == false) ? ".\(pathExtension!)" : ""
        var candidate = directory.appendingPathComponent(baseName + suffix)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter)\(suffix)")
            counter += 1
        }
        return candidate
    }

    public static func uniqueDestination(for source: URL, in directory: URL, duplicate: Bool) -> URL {
        let ext = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent
        let base = duplicate ? stem + " copy" : stem
        return uniqueURL(in: directory, baseName: base, pathExtension: ext.isEmpty ? nil : ext)
    }
}
