import XCTest
@testable import ExplorerCore

final class BatchRenameTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchRenameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testFindReplacePreservesExtensions() {
        let a = tempDirectory.appendingPathComponent("report-one.txt")
        let b = tempDirectory.appendingPathComponent("report-two.md")
        let items = [BatchRenameItem(url: a, isDirectory: false), BatchRenameItem(url: b, isDirectory: false)]
        var options = BatchRenameOptions()
        options.mode = .findReplace
        options.find = "report"
        options.replace = "summary"
        let preview = BatchRenamePlanner.preview(items: items, options: options)
        XCTAssertEqual(preview.map(\.newName), ["summary-one.txt", "summary-two.md"])
    }

    func testPrefixAndNumbering() {
        let item = BatchRenameItem(url: tempDirectory.appendingPathComponent("Draft.txt"), isDirectory: false)
        var prefixOptions = BatchRenameOptions()
        prefixOptions.mode = .addText
        prefixOptions.prefix = "Final-"
        prefixOptions.suffix = "-v2"
        XCTAssertEqual(
            BatchRenamePlanner.preview(items: [item], options: prefixOptions).first?.newName,
            "Final-Draft-v2.txt"
        )

        var numberOptions = BatchRenameOptions()
        numberOptions.mode = .number
        numberOptions.numberBase = "Photo"
        numberOptions.numberStart = 1
        numberOptions.numberPadding = 3
        let second = BatchRenameItem(url: tempDirectory.appendingPathComponent("Other.jpg"), isDirectory: false)
        let numbered = BatchRenamePlanner.preview(items: [item, second], options: numberOptions)
        XCTAssertEqual(numbered.map(\.newName), ["Photo 001.txt", "Photo 002.jpg"])
    }

    func testDuplicateAndExistingNamesAreRejected() throws {
        let firstDirectory = tempDirectory.appendingPathComponent("One", isDirectory: true)
        let secondDirectory = tempDirectory.appendingPathComponent("Two", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let existing = firstDirectory.appendingPathComponent("Taken.txt")
        try Data().write(to: existing)
        let a = firstDirectory.appendingPathComponent("report.txt")
        let b = secondDirectory.appendingPathComponent("report.txt")
        try Data().write(to: a)
        try Data().write(to: b)
        let items = [BatchRenameItem(url: a, isDirectory: false), BatchRenameItem(url: b, isDirectory: false)]

        var duplicateOptions = BatchRenameOptions()
        duplicateOptions.mode = .findReplace
        duplicateOptions.find = "report"
        duplicateOptions.replace = "same"
        let duplicate = BatchRenamePlanner.preview(items: items, options: duplicateOptions)
        XCTAssertTrue(duplicate.contains { $0.error?.contains("Multiple items") == true })

        var existingOptions = BatchRenameOptions()
        existingOptions.mode = .findReplace
        existingOptions.find = "report"
        existingOptions.replace = "Taken"
        let collision = BatchRenamePlanner.preview(items: [items[0]], options: existingOptions)
        XCTAssertNotNil(collision.first?.error)
    }
}
