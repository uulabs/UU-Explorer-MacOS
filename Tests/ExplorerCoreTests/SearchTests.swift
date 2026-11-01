import XCTest
@testable import ExplorerCore

final class SearchTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let nested = tempDirectory.appendingPathComponent("Projects/Alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: tempDirectory.appendingPathComponent("Report.txt"))
        try Data("two".utf8).write(to: tempDirectory.appendingPathComponent("report-notes.md"))
        try Data("three".utf8).write(to: nested.appendingPathComponent("ReportFinal.txt"))
        try Data("hidden".utf8).write(to: tempDirectory.appendingPathComponent(".ReportHidden.txt"))
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testRecursiveSearchFindsNestedMatchesAndSkipsHiddenByDefault() {
        let results = FileSystemService.recursiveSearch(at: tempDirectory, matching: "report")
        XCTAssertEqual(
            results.map(\.name).sorted(),
            ["Report.txt", "ReportFinal.txt", "report-notes.md"].sorted()
        )
    }

    func testRecursiveSearchHonorsLimitAndCanIncludeHidden() {
        let limited = FileSystemService.recursiveSearch(at: tempDirectory, matching: "report", limit: 1)
        XCTAssertEqual(limited.count, 1)

        let hidden = FileSystemService.recursiveSearch(
            at: tempDirectory,
            matching: "ReportHidden",
            includeHidden: true
        )
        XCTAssertEqual(hidden.map(\.name), [".ReportHidden.txt"])
    }
}
