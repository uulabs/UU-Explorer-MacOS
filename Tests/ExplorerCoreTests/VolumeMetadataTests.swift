import XCTest
@testable import ExplorerCore

final class VolumeMetadataTests: XCTestCase {
    func testRootVolumeIsDetectedWithCapacityAndFormat() throws {
        let volume = try XCTUnwrap(VolumeMetadata.load(for: URL(fileURLWithPath: "/")))
        XCTAssertEqual(volume.mountPoint, "/")
        XCTAssertTrue(volume.isRootFileSystem)
        XCTAssertTrue(volume.isInternal)
        XCTAssertFalse(volume.format.isEmpty)
        XCTAssertGreaterThan(volume.totalCapacity ?? 0, 0)
        XCTAssertNotNil(volume.usedCapacity)
    }

    func testOrdinaryFolderIsNotAVolume() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VolumeMetadataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(VolumeMetadata.load(for: folder))
        XCTAssertFalse(VolumeMetadata.isVolumeRoot(folder))
    }
}
