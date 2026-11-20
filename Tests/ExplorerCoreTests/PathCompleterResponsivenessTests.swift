import XCTest
@testable import ExplorerCore

final class PathCompleterResponsivenessTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathCompleterResponsivenessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testCancelledCompletionReturnsNoSuggestions() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Match", isDirectory: true),
            withIntermediateDirectories: false
        )

        let suggestions = PathCompleter.suggestions(
            for: "Mat",
            base: tempDirectory,
            isCancelled: { true }
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testScanLimitBoundsDirectoryEnumeration() throws {
        for index in 0..<12 {
            try FileManager.default.createDirectory(
                at: tempDirectory.appendingPathComponent("Match\(index)", isDirectory: true),
                withIntermediateDirectories: false
            )
        }

        let suggestions = PathCompleter.suggestions(
            for: tempDirectory.path + "/",
            base: tempDirectory,
            limit: 20,
            parentLimit: 0,
            scanLimit: 3
        )

        XCTAssertEqual(suggestions.count, 3)
        XCTAssertTrue(suggestions.allSatisfy { $0.name.hasPrefix("Match") })
    }

    func testZeroScanLimitStillOffersParents() throws {
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Match", isDirectory: true),
            withIntermediateDirectories: false
        )

        let suggestions = PathCompleter.suggestions(
            for: "Mat",
            base: tempDirectory,
            parentLimit: 1,
            scanLimit: 0
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.kind, .parent)
    }
}
