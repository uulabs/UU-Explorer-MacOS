import XCTest
@testable import ExplorerCore

final class FolderTreeTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testTreeListsOnlyFoldersAndSortsNaturally() throws {
        for name in ["Folder10", "Folder2", ".hidden", "Example.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("file.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
        let entries = try FileSystemService.folderChildren(at: root)
        XCTAssertEqual(entries.map(\.name), ["Folder2", "Folder10"])
        XCTAssertEqual(try FileSystemService.folderChildren(at: root, includeHidden: true).map(\.name),
                       [".hidden", "Folder2", "Folder10"])
    }

    func testMissingFolderThrowsButEmptyFolderReturnsEmptyList() throws {
        XCTAssertTrue(try FileSystemService.folderChildren(at: root).isEmpty)
        XCTAssertThrowsError(try FileSystemService.folderChildren(at: root.appendingPathComponent("missing")))
    }

    func testSidebarLimitIsAppliedAfterSorting() throws {
        for name in ["Zulu", "Alpha", "Beta"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        XCTAssertEqual(FileSystemService.subdirectories(at: root, limit: 1).map(\.name), ["Alpha"])
        XCTAssertTrue(FileSystemService.subdirectories(at: root, limit: 0).isEmpty)
    }
}
