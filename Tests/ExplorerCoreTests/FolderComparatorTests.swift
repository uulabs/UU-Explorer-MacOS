import XCTest
@testable import ExplorerCore

final class FolderComparatorTests: XCTestCase {
    private func item(_ name: String, size: Int64?, directory: Bool = false, date: Date = Date()) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            isDirectory: directory,
            isPackage: false,
            isHidden: false,
            isSymbolicLink: false,
            isApplication: false,
            dateModified: date,
            byteSize: size,
            kind: directory ? "Folder" : "text"
        )
    }

    func testComparesSides() {
        let date = Date()
        let left = [item("same.txt", size: 10, date: date), item("left.txt", size: 4, date: date), item("changed.txt", size: 5, date: date)]
        let right = [item("same.txt", size: 10, date: date), item("right.txt", size: 4, date: date), item("changed.txt", size: 9, date: date)]
        let result = FolderComparator.compare(left: left, right: right)
        XCTAssertEqual(result.first(where: { $0.name == "same.txt" })?.state, .identical)
        XCTAssertEqual(result.first(where: { $0.name == "left.txt" })?.state, .leftOnly)
        XCTAssertEqual(result.first(where: { $0.name == "right.txt" })?.state, .rightOnly)
        XCTAssertEqual(result.first(where: { $0.name == "changed.txt" })?.state, .different)
    }

    func testDirectoriesPresentOnBothSidesAreIdentical() {
        let left = [item("Folder", size: nil, directory: true)]
        let right = [item("Folder", size: nil, directory: true)]
        XCTAssertEqual(FolderComparator.compare(left: left, right: right).first?.state, .identical)
    }
}
