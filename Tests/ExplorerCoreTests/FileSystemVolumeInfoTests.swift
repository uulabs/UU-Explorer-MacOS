import XCTest
@testable import ExplorerCore

final class FileSystemVolumeInfoTests: XCTestCase {
    func testNestedDirectoryUsesTargetContainingVolume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSystemVolumeInfoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = try XCTUnwrap(FileSystemService.volumeInfo(for: URL(fileURLWithPath: "/")))
        let nested = try XCTUnwrap(FileSystemService.volumeInfo(for: directory))

        XCTAssertEqual(nested.rootURL.standardizedFileURL, root.rootURL.standardizedFileURL)
        XCTAssertEqual(nested.name, root.name)
        XCTAssertEqual(nested.isInternal, root.isInternal)
        XCTAssertNotNil(nested.totalCapacity)
    }
}
