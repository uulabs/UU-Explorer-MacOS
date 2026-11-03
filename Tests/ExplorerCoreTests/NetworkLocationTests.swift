import XCTest
@testable import ExplorerCore

final class NetworkLocationTests: XCTestCase {
    func testAddsSMBWhenSchemeIsOmitted() throws {
        let location = try NetworkLocation.parse(address: "nas.local/Media", name: "Media NAS")
        XCTAssertEqual(location.protocolName, .smb)
        XCTAssertEqual(location.name, "Media NAS")
        XCTAssertEqual(location.urlString, "smb://nas.local/Media")
    }

    func testSupportsAFPAndNFS() throws {
        let afp = try NetworkLocation.parse(address: "afp://server.local/Share")
        XCTAssertEqual(afp.protocolName, .afp)
        XCTAssertEqual(afp.name, "server.local/Share")

        let nfs = try NetworkLocation.parse(address: "nfs://server.local/export")
        XCTAssertEqual(nfs.protocolName, .nfs)
        XCTAssertEqual(nfs.url?.path, "/export")
    }

    func testAutoConnectDefaultsForOlderSavedLocations() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Media","urlString":"smb://nas/Media","protocolName":"smb"}"#
        let location = try JSONDecoder().decode(NetworkLocation.self, from: Data(json.utf8))
        XCTAssertFalse(location.autoConnect)

        let explicit = try NetworkLocation.parse(
            address: "smb://nas/Media",
            name: "Media",
            autoConnect: true
        )
        XCTAssertTrue(explicit.autoConnect)
    }

    func testRejectsUnsupportedOrEmptyInput() {
        XCTAssertThrowsError(try NetworkLocation.parse(address: "https://example.com"))
        XCTAssertThrowsError(try NetworkLocation.parse(address: ""))
        XCTAssertThrowsError(try NetworkLocation.parse(address: "smb://"))
    }
}
