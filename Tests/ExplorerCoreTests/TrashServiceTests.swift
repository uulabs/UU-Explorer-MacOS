import XCTest
@testable import ExplorerCore

final class TrashServiceTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrashServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    func testVolumeTrashFallbackMovesFile() throws {
        let source = tempDirectory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("note.txt")
        try Data("trash".utf8).write(to: file)

        let destination = try TrashService.moveToVolumeTrash(file, volumeRoot: tempDirectory)
        let expected = tempDirectory
            .appendingPathComponent(".Trashes/\(getuid())/note.txt")
        XCTAssertEqual(destination.standardizedFileURL.path, expected.standardizedFileURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "trash")
    }

    func testVolumeTrashFallbackAvoidsNameCollisions() throws {
        let uidTrash = tempDirectory
            .appendingPathComponent(".Trashes/\(getuid())", isDirectory: true)
        try FileManager.default.createDirectory(at: uidTrash, withIntermediateDirectories: true)
        try Data().write(to: uidTrash.appendingPathComponent("note.txt"))

        let source = tempDirectory.appendingPathComponent("note.txt")
        try Data("new".utf8).write(to: source)
        let destination = try TrashService.moveToVolumeTrash(source, volumeRoot: tempDirectory)
        XCTAssertEqual(destination.lastPathComponent, "note 2.txt")
    }

    func testEmptyVolumeTrashRemovesContentsButKeepsDirectory() throws {
        let trash = TrashService.volumeTrashURL(for: tempDirectory)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: trash.appendingPathComponent("one"))
        try Data("two".utf8).write(to: trash.appendingPathComponent("two"))
        XCTAssertEqual(try TrashService.emptyVolumeTrash(volumeRoot: tempDirectory), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path).count, 0)
    }

    func testPermanentDeleteRemovesItem() throws {
        let target = tempDirectory.appendingPathComponent("target")
        try Data("delete".utf8).write(to: target)
        try TrashService.permanentDelete(target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
}
