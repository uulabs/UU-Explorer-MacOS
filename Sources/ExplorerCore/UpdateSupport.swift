import CryptoKit
import Foundation

public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") { value.removeFirst() }
        if let separator = value.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            value = String(value[..<separator])
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        while numbers.count < 3 { numbers.append(0) }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public struct GitHubReleaseAsset: Decodable, Sendable, Equatable {
    public let name: String
    public let browserDownloadURL: URL

    public init(name: String, browserDownloadURL: URL) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let assets: [GitHubReleaseAsset]
    public let prerelease: Bool
    public let draft: Bool

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        htmlURL: URL,
        assets: [GitHubReleaseAsset],
        prerelease: Bool = false,
        draft: Bool = false
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.htmlURL = htmlURL
        self.assets = assets
        self.prerelease = prerelease
        self.draft = draft
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
        case prerelease
        case draft
    }
}

public struct UpdateRelease: Sendable, Equatable {
    public let version: AppVersion
    public let tag: String
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let archiveName: String
    public let archiveURL: URL
    public let checksumName: String
    public let checksumURL: URL
}

public enum UpdateReleaseSelector {
    /// Selects a stable release published with a ZIP and its `.sha256` sidecar.
    /// Drafts, pre-releases, non-HTTPS assets, and incomplete checksum pairs are
    /// rejected before any download is attempted.
    public static func select(from release: GitHubRelease) -> UpdateRelease? {
        guard !release.draft, !release.prerelease,
              let version = AppVersion(release.tagName) else { return nil }
        let assets = release.assets.filter {
            $0.browserDownloadURL.scheme?.lowercased() == "https"
        }
        guard let archive = assets.first(where: {
            let name = $0.name.lowercased()
            return name.hasSuffix(".zip") && !name.hasSuffix(".sha256")
        }),
        let checksum = assets.first(where: { $0.name == archive.name + ".sha256" }) else {
            return nil
        }
        return UpdateRelease(
            version: version,
            tag: release.tagName,
            title: release.name ?? release.tagName,
            notes: release.body ?? "",
            pageURL: release.htmlURL,
            archiveName: archive.name,
            archiveURL: archive.browserDownloadURL,
            checksumName: checksum.name,
            checksumURL: checksum.browserDownloadURL
        )
    }
}

public enum SHA256Checksum {
    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func parseSidecar(_ text: String) -> String? {
        let pattern = try? NSRegularExpression(pattern: "(?i)\\b[0-9a-f]{64}\\b")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = pattern?.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text) else { return nil }
        return String(text[matchRange]).lowercased()
    }

    public static func verify(data: Data, expectedHex: String) -> Bool {
        hex(data).caseInsensitiveCompare(expectedHex.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }
}
