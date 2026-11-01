import CryptoKit
import Foundation

public enum TransferMetrics {
    /// Sums logical regular-file bytes recursively. Directory metadata and
    /// symlink payloads are not included.
    public static func totalLogicalBytes(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true {
            return Int64(values.fileSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            guard let values = try? child.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory == true || values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    public static func totalLogicalBytes(at urls: [URL]) -> Int64 {
        urls.reduce(into: Int64(0)) { $0 += totalLogicalBytes(at: $1) }
    }
}

public enum TransferVerifier {
    /// A stable SHA-256 tree fingerprint. Paths are included so identical file
    /// contents in different locations do not compare equal.
    public static func fingerprint(at url: URL) -> String? {
        var hasher = SHA256()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        if values.isDirectory == true {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: []
            ) else { return nil }
            var entries: [(path: String, url: URL)] = []
            for case let child as URL in enumerator {
                let relative = child.path.hasPrefix(url.path + "/")
                    ? String(child.path.dropFirst(url.path.count + 1))
                    : child.lastPathComponent
                entries.append((relative, child))
            }
            entries.sort { $0.path < $1.path }
            for entry in entries {
                guard let entryValues = try? entry.url.resourceValues(forKeys: keys) else { return nil }
                update(&hasher, entry.path)
                if entryValues.isDirectory == true {
                    update(&hasher, "d")
                } else if entryValues.isSymbolicLink == true {
                    update(&hasher, "l")
                    if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.url.path) {
                        update(&hasher, destination)
                    }
                } else if entryValues.isRegularFile == true {
                    update(&hasher, "f")
                    guard hashFile(at: entry.url, into: &hasher) else { return nil }
                } else {
                    update(&hasher, "o")
                }
            }
        } else if values.isSymbolicLink == true {
            update(&hasher, "l")
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
                update(&hasher, destination)
            }
        } else if values.isRegularFile == true {
            update(&hasher, "f")
            guard hashFile(at: url, into: &hasher) else { return nil }
        } else {
            update(&hasher, "o")
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func verify(source: URL, target: URL) -> Bool {
        guard let left = fingerprint(at: source), let right = fingerprint(at: target) else {
            return false
        }
        return left == right
    }

    private static func update(_ hasher: inout SHA256, _ value: String) {
        hasher.update(data: Data(value.utf8))
        hasher.update(data: Data([0]))
    }

    private static func hashFile(at url: URL, into hasher: inout SHA256) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        while true {
            let data: Data?
            do {
                data = try handle.read(upToCount: 1_048_576)
            } catch {
                return false
            }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return true
    }
}
