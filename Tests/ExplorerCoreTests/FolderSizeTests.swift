import XCTest
@testable import ExplorerCore

final class FolderSizeTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderSizeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    func testSumsLogicalSizesAndCounts() throws {
        try Data(repeating: 1, count: 1_200).write(to: root.appendingPathComponent("one.bin"))
        try Data(repeating: 2, count: 345).write(to: root.appendingPathComponent("two.bin"))
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 55).write(to: nested.appendingPathComponent("three.bin"))

        let size = FolderSizeService.calculate(at: root)
        XCTAssertEqual(size.bytes, 1_600)
        XCTAssertEqual(size.fileCount, 3)
        XCTAssertEqual(size.directoryCount, 1)
        XCTAssertGreaterThanOrEqual(size.allocatedBytes, size.bytes)
    }

    func testCancellationStopsScan() {
        var calls = 0
        let size = FolderSizeService.calculate(at: root) {
            calls += 1
            return true
        }
        XCTAssertEqual(size.fileCount, 0)
        XCTAssertLessThanOrEqual(calls, 1)
    }

    func testEmptyFolder() {
        let size = FolderSizeService.calculate(at: root)
        XCTAssertEqual(size, FolderSize(bytes: 0, allocatedBytes: 0, fileCount: 0, directoryCount: 0))
    }
}
