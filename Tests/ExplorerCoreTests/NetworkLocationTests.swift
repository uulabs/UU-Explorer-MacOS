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

    func testRejectsUnsupportedOrEmptyInput() {
        XCTAssertThrowsError(try NetworkLocation.parse(address: "https://example.com"))
        XCTAssertThrowsError(try NetworkLocation.parse(address: ""))
        XCTAssertThrowsError(try NetworkLocation.parse(address: "smb://"))
    }
}
