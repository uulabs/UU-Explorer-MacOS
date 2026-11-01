import XCTest
@testable import ExplorerCore

final class UpdateSupportTests: XCTestCase {
    func testVersionOrdering() throws {
        XCTAssertEqual(try XCTUnwrap(AppVersion("v1.19.0")), try XCTUnwrap(AppVersion("1.19")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.18.3")), try XCTUnwrap(AppVersion("1.19.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.19.0")), try XCTUnwrap(AppVersion("1.19.1")))
        XCTAssertNil(AppVersion("not-a-version"))
    }

    func testReleaseSelectionRequiresZipAndChecksum() throws {
        let page = try XCTUnwrap(URL(string: "https://github.com/uulabs/UU-Explorer-MacOS/releases/tag/v1.19.0"))
        let zip = try XCTUnwrap(URL(string: "https://github.com/uulabs/UU-Explorer-MacOS/releases/download/v1.19.0/UU-Explorer-1.19.0.zip"))
        let sum = try XCTUnwrap(URL(string: "https://github.com/uulabs/UU-Explorer-MacOS/releases/download/v1.19.0/UU-Explorer-1.19.0.zip.sha256"))
        let release = GitHubRelease(
            tagName: "v1.19.0",
            name: "UU Explorer 1.19.0",
            body: "Notes",
            htmlURL: page,
            assets: [
                GitHubReleaseAsset(name: "UU-Explorer-1.19.0.zip", browserDownloadURL: zip),
                GitHubReleaseAsset(name: "UU-Explorer-1.19.0.zip.sha256", browserDownloadURL: sum)
            ]
        )
        let selected = try XCTUnwrap(UpdateReleaseSelector.select(from: release))
        XCTAssertEqual(selected.version.description, "1.19.0")
        XCTAssertEqual(selected.archiveName, "UU-Explorer-1.19.0.zip")
        XCTAssertEqual(selected.checksumName, "UU-Explorer-1.19.0.zip.sha256")

        let noChecksum = GitHubRelease(
            tagName: "v1.19.1", htmlURL: page,
            assets: [GitHubReleaseAsset(name: "UU-Explorer-1.19.1.zip", browserDownloadURL: zip)]
        )
        XCTAssertNil(UpdateReleaseSelector.select(from: noChecksum))
    }

    func testChecksumParsingAndVerification() {
        let data = Data("hello update".utf8)
        let digest = SHA256Checksum.hex(data)
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(SHA256Checksum.parseSidecar("\(digest)  UU-Explorer-1.19.0.zip"), digest)
        XCTAssertTrue(SHA256Checksum.verify(data: data, expectedHex: digest))
        XCTAssertFalse(SHA256Checksum.verify(data: data, expectedHex: String(repeating: "0", count: 64)))
    }
}
