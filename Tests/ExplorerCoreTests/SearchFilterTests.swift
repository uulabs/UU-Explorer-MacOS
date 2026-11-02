import XCTest
@testable import ExplorerCore

final class SearchFilterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchFilterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        root = nil
        try super.tearDownWithError()
    }

    func testLargeFileSearchWithEmptyQuery() throws {
        try Data(repeating: 1, count: 32).write(to: root.appendingPathComponent("small.txt"))
        try Data(repeating: 2, count: 4096).write(to: root.appendingPathComponent("large.bin"))
        let results = FileSystemService.search(
            at: root,
            matching: "",
            filter: SearchFilter(minimumSize: 1_000)
        )
        XCTAssertEqual(results.map(\.name), ["large.bin"])
    }

    func testFilenameAndKindFilter() throws {
        try Data("text".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try Data(repeating: 3, count: 64).write(to: root.appendingPathComponent("photo.png"))
        let results = FileSystemService.search(
            at: root,
            matching: "photo",
            filter: SearchFilter(kind: .image)
        )
        XCTAssertEqual(results.map(\.name), ["photo.png"])
    }

    func testSearchStopsWhenCancelledAndReportsProgress() throws {
        for index in 0..<120 {
            try Data([UInt8(index % 255)]).write(to: root.appendingPathComponent("item-\(index).bin"))
        }
        var progress = 0
        let cancelled = FileSystemService.search(
            at: root,
            matching: "",
            filter: SearchFilter(minimumSize: 0),
            limit: 100,
            isCancelled: { true },
            onProgress: { scanned, _ in progress = scanned }
        )
        XCTAssertTrue(cancelled.isEmpty)

        var scanned = 0
        let results = FileSystemService.search(
            at: root,
            matching: "",
            filter: SearchFilter(minimumSize: 0),
            limit: 20,
            isCancelled: { false },
            onProgress: { count, _ in scanned = count }
        )
        XCTAssertEqual(results.count, 20)
        XCTAssertGreaterThan(scanned, 0)
    }

    func testDateFilter() throws {
        let old = root.appendingPathComponent("old.txt")
        try Data("old".utf8).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-40 * 86_400)],
            ofItemAtPath: old.path
        )
        let results = FileSystemService.search(
            at: root,
            matching: "old",
            filter: SearchFilter(modifiedWithinDays: 30)
        )
        XCTAssertTrue(results.isEmpty)
    }
}
