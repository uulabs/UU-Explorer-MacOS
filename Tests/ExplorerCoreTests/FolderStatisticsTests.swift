import XCTest
@testable import ExplorerCore

final class FolderStatisticsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testRecursiveTotalsIncludeHiddenFilesAndPackages() throws {
        let subfolder = root.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 123).write(to: subfolder.appendingPathComponent("file"))
        try Data(repeating: 2, count: 77).write(to: root.appendingPathComponent(".hidden"))
        let result = FolderStatistics.calculate(at: root)
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(result.folderCount, 1)
        XCTAssertEqual(result.logicalBytes, 200)
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.inaccessibleCount, 0)
    }

    func testSymbolicLinkCycleIsNotTraversed() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let result = FolderStatistics.calculate(at: root)
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.folderCount, 0)
        XCTAssertEqual(result.symbolicLinkCount, 1)
        XCTAssertTrue(result.isComplete)
    }

    func testUnreadableSubfolderReportsPartialTotals() throws {
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: locked.appendingPathComponent("secret"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        guard !FileManager.default.isReadableFile(atPath: locked.path) else {
            throw XCTSkip("Test process can read restricted folders")
        }
        let result = FolderStatistics.calculate(at: root)
        XCTAssertGreaterThan(result.inaccessibleCount, 0)
        XCTAssertEqual(result.logicalBytes, 0)
    }

    func testHardLinksCountAllocatedBlocksOnce() throws {
        let file = root.appendingPathComponent("original")
        try Data(repeating: 1, count: 8192).write(to: file)
        let single = FolderStatistics.calculate(at: root)
        try FileManager.default.linkItem(at: file, to: root.appendingPathComponent("link"))
        let result = FolderStatistics.calculate(at: root)
        XCTAssertEqual(result.fileCount, 2)
        XCTAssertEqual(result.logicalBytes, 16384)
        XCTAssertEqual(result.allocatedBytes, single.allocatedBytes)
    }

    func testSparseFileReportsLogicalAndAllocatedSizesSeparately() throws {
        let url = root.appendingPathComponent("sparse")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 10_000_000)
        try file.close()
        let result = FolderStatistics.calculate(at: root)
        XCTAssertEqual(result.logicalBytes, 10_000_000)
        XCTAssertLessThan(result.allocatedBytes, result.logicalBytes)
    }

    func testCancelledScanDoesNotReportCompletion() {
        let result = FolderStatistics.calculate(at: root, isCancelled: { true })
        XCTAssertTrue(result.isCancelled)
        XCTAssertFalse(result.isComplete)
    }

    func testMissingRootReportsIncompleteCoverage() {
        let result = FolderStatistics.calculate(at: root.appendingPathComponent("missing"))
        XCTAssertEqual(result.inaccessibleCount, 1)
        XCTAssertEqual(result.logicalBytes, 0)
    }
}
