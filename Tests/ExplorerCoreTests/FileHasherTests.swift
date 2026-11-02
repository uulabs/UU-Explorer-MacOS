import XCTest
@testable import ExplorerCore

final class FileHasherTests: XCTestCase {
    func testSHA256() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileHasherTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(
            FileHasher.sha256(at: url),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}
