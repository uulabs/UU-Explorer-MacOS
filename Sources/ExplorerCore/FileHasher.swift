import CryptoKit
import Foundation

public enum FileHasher {
    public static func sha256(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data: Data?
            do {
                data = try handle.read(upToCount: 1_048_576)
            } catch {
                return nil
            }
            guard let data, !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
