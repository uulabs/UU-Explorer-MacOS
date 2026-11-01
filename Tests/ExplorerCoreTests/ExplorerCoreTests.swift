import XCTest
@testable import ExplorerCore

final class ExplorerCoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplorerCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Paths

    func testExpandsAbsoluteTildeAndRelativePaths() {
        let home = URL(fileURLWithPath: "/Users/example")
        let base = URL(fileURLWithPath: "/Users/example/Work")

        XCTAssertEqual(PathTools.expand("/usr/local", home: home)?.path, "/usr/local")
        XCTAssertEqual(PathTools.expand("~", home: home)?.path, "/Users/example")
        XCTAssertEqual(PathTools.expand("~/Documents", home: home)?.path, "/Users/example/Documents")
        XCTAssertEqual(PathTools.expand("Project/Docs", relativeTo: base, home: home)?.path, "/Users/example/Work/Project/Docs")
        XCTAssertEqual(PathTools.expand("../Other", relativeTo: base, home: home)?.path, "/Users/example/Other")
        XCTAssertNil(PathTools.expand("   ", relativeTo: base, home: home))
        XCTAssertNil(PathTools.expand("relative", home: home))
    }

    func testBreadcrumbsStartAtVolumeRoot() {
        let root = URL(fileURLWithPath: "/Users/example")
        let deep = URL(fileURLWithPath: "/Users/example/Work/Project")

        let crumbs = PathTools.breadcrumbs(for: deep, volumeRoot: root, volumeName: "Macintosh HD")
        XCTAssertEqual(crumbs.map(\.name), ["Macintosh HD", "Work", "Project"])
        XCTAssertEqual(crumbs.map(\.path), ["/Users/example", "/Users/example/Work", "/Users/example/Work/Project"])
    }

    func testBreadcrumbsFallBackToRootWhenVolumeIsUnrelated() {
        let crumbs = PathTools.breadcrumbs(
            for: URL(fileURLWithPath: "/etc/hosts"),
            volumeRoot: URL(fileURLWithPath: "/Users/example"),
            volumeName: "Macintosh HD"
        )
        XCTAssertEqual(crumbs.first?.path, "/")
        XCTAssertEqual(crumbs.map(\.name), ["Macintosh HD", "etc", "hosts"])
    }

    func testDescendantDetection() {
        XCTAssertTrue(PathTools.isDescendant(URL(fileURLWithPath: "/Users/example/Work"), of: URL(fileURLWithPath: "/")))
        XCTAssertTrue(PathTools.isDescendant(URL(fileURLWithPath: "/Users/example/Work"), of: URL(fileURLWithPath: "/Users/example")))
        XCTAssertFalse(PathTools.isDescendant(URL(fileURLWithPath: "/Users/example2"), of: URL(fileURLWithPath: "/Users/example")))
        XCTAssertEqual(PathTools.parent(of: URL(fileURLWithPath: "/"))?.path, nil)
        XCTAssertEqual(PathTools.parent(of: URL(fileURLWithPath: "/Users"))?.path, "/")
    }

    // MARK: - Formatting

    func testByteFormatting() {
        XCTAssertEqual(ByteFormat.string(nil), "—")
        XCTAssertEqual(ByteFormat.string(0), "0 B")
        XCTAssertEqual(ByteFormat.string(999), "999 B")
        XCTAssertEqual(ByteFormat.string(1_000), "1.0 KB")
        XCTAssertEqual(ByteFormat.string(1_500), "1.5 KB")
        XCTAssertEqual(ByteFormat.string(15_000), "15 KB")
        XCTAssertEqual(ByteFormat.string(1_500_000), "1.5 MB")
        XCTAssertEqual(ByteFormat.string(2_000_000_000), "2.0 GB")
    }

    // MARK: - Sorting

    private func makeItem(
        _ name: String,
        directory: Bool = false,
        size: Int64? = nil,
        date: Date? = nil,
        kind: String = "File"
    ) -> FileItem {
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
            kind: kind
        )
    }

    func testFoldersAlwaysSortFirstAndNamesSortNaturally() {
        let items = [
            makeItem("file10.txt", size: 10),
            makeItem("Beta", directory: true),
            makeItem("file2.txt", size: 20),
            makeItem("alpha", directory: true),
            makeItem("File1.txt", size: 30)
        ]
        let sorted = FileSorter.sorted(items, by: .name, ascending: true)
        XCTAssertEqual(sorted.map(\.name), ["alpha", "Beta", "File1.txt", "file2.txt", "file10.txt"])
    }

    func testDescendingKeepsFoldersFirstAndMissingSizesLast() {
        let items = [
            makeItem("A", directory: true),
            makeItem("big.bin", size: 5_000),
            makeItem("small.bin", size: 10),
            makeItem("unknown.bin", size: nil)
        ]
        let sorted = FileSorter.sorted(items, by: .size, ascending: false)
        XCTAssertEqual(sorted.map(\.name), ["A", "big.bin", "small.bin", "unknown.bin"])
    }

    func testSortsByDateWithMissingDatesLast() {
        let now = Date()
        let items = [
            makeItem("old.txt", date: now.addingTimeInterval(-100)),
            makeItem("new.txt", date: now),
            makeItem("undated.txt", date: nil)
        ]
        XCTAssertEqual(FileSorter.sorted(items, by: .dateModified, ascending: true).map(\.name), ["old.txt", "new.txt", "undated.txt"])
        XCTAssertEqual(FileSorter.sorted(items, by: .dateModified, ascending: false).map(\.name), ["new.txt", "old.txt", "undated.txt"])
    }

    // MARK: - Listing

    func testDirectoryListingIncludesHiddenOnlyWhenRequested() throws {
        try Data(count: 1_234).write(to: tempDirectory.appendingPathComponent("notes.txt"))
        try FileManager.default.createDirectory(
            at: tempDirectory.appendingPathComponent("Folder"),
            withIntermediateDirectories: false
        )
        try Data("secret".utf8).write(to: tempDirectory.appendingPathComponent(".hidden"))

        let visible = try FileSystemService.listDirectory(at: tempDirectory)
        XCTAssertEqual(Set(visible.map(\.name)), ["notes.txt", "Folder"])
        let file = try XCTUnwrap(visible.first { $0.name == "notes.txt" })
        XCTAssertFalse(file.isDirectory)
        XCTAssertEqual(file.byteSize, 1_234)
        XCTAssertFalse(file.kind.isEmpty)

        let folder = try XCTUnwrap(visible.first { $0.name == "Folder" })
        XCTAssertTrue(folder.isDirectory)
        XCTAssertNil(folder.byteSize)

        let all = try FileSystemService.listDirectory(at: tempDirectory, includeHidden: true)
        XCTAssertEqual(Set(all.map(\.name)), ["notes.txt", "Folder", ".hidden"])
    }

    func testSubdirectoriesAreSortedAndExcludeFiles() throws {
        for name in ["zulu", "alpha", "mike"] {
            try FileManager.default.createDirectory(
                at: tempDirectory.appendingPathComponent(name),
                withIntermediateDirectories: false
            )
        }
        try Data().write(to: tempDirectory.appendingPathComponent("file.txt"))

        let entries = FileSystemService.subdirectories(at: tempDirectory)
        XCTAssertEqual(entries.map(\.name), ["alpha", "mike", "zulu"])
    }

    // MARK: - Naming

    func testValidationRejectsUnsafeNames() {
        XCTAssertNil(FileName.validationError(for: "Beach Photos"))
        XCTAssertNotNil(FileName.validationError(for: ""))
        XCTAssertNotNil(FileName.validationError(for: "a/b"))
        XCTAssertNotNil(FileName.validationError(for: "a:b"))
        XCTAssertNotNil(FileName.validationError(for: " name"))
        XCTAssertNotNil(FileName.validationError(for: "name "))
        XCTAssertNotNil(FileName.validationError(for: "."))
        XCTAssertNotNil(FileName.validationError(for: ".."))
        XCTAssertNotNil(FileName.validationError(for: String(repeating: "a", count: 256)))
    }

    func testUniqueNamesAvoidCollisions() throws {
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Folder 2"), withIntermediateDirectories: false)
        let folder = FileName.uniqueURL(in: tempDirectory, baseName: "Folder")
        XCTAssertEqual(folder.lastPathComponent, "Folder 3")

        try Data().write(to: tempDirectory.appendingPathComponent("report.txt"))
        try Data().write(to: tempDirectory.appendingPathComponent("report copy.txt"))
        let copy = FileName.uniqueURL(in: tempDirectory, baseName: "report copy", pathExtension: "txt")
        XCTAssertEqual(copy.lastPathComponent, "report copy 2.txt")

        let destination = FileName.uniqueDestination(
            for: tempDirectory.appendingPathComponent("report.txt"),
            in: tempDirectory,
            duplicate: false
        )
        XCTAssertEqual(destination.lastPathComponent, "report 2.txt")
    }

    // MARK: - Path completion

    func testPathCompletionSuggestsDirectoriesFirst() throws {
        for name in ["Documents", "Downloads", "notes.txt", "Doobly"] {
            let url = tempDirectory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        try FileManager.default.createDirectory(at: tempDirectory.appendingPathComponent("Doobly/Inner"), withIntermediateDirectories: false)

        let relative = PathCompleter.suggestions(for: "Do", base: tempDirectory)
        XCTAssertEqual(relative.filter { $0.kind != .parent }.map(\.name), ["Documents", "Doobly", "Downloads"])
        XCTAssertTrue(relative.filter { $0.kind != .parent }.allSatisfy(\.isDirectory))
        XCTAssertEqual(relative.first?.kind, .parent)
        XCTAssertEqual(relative.first?.url.path, tempDirectory.deletingLastPathComponent().path)

        let absolutePrefix = tempDirectory.path + "/Down"
        let absolute = PathCompleter.suggestions(for: absolutePrefix, base: tempDirectory)
        XCTAssertEqual(absolute.filter { $0.kind != .parent }.map(\.name), ["Downloads"])

        let trailingSlash = PathCompleter.suggestions(for: tempDirectory.path + "/Doobly/", base: tempDirectory)
        XCTAssertEqual(trailingSlash.filter { $0.kind != .parent }.map(\.name), ["Inner"])

        let missing = PathCompleter.suggestions(for: tempDirectory.path + "/Missing", base: tempDirectory)
        XCTAssertTrue(missing.filter { $0.kind != .parent }.isEmpty)
        XCTAssertEqual(missing.first?.kind, .parent)
    }

    func testPathCompletionOffersAncestorFolders() throws {
        let outer = tempDirectory.appendingPathComponent("Outer", isDirectory: true)
        let inner = outer.appendingPathComponent("Inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)

        let suggestions = PathCompleter.suggestions(
            for: inner.path + "/",
            base: tempDirectory,
            parentLimit: 4
        )
        let parents = suggestions.filter { $0.kind == .parent }
        XCTAssertEqual(parents.first?.url.path, outer.path)
        XCTAssertEqual(parents.first?.name, "Outer")
        XCTAssertEqual(parents.count, 4)
        XCTAssertTrue(parents.allSatisfy(\.isDirectory))

        let rootOnly = PathCompleter.suggestions(for: "/", base: tempDirectory, parentLimit: 4)
        XCTAssertTrue(rootOnly.allSatisfy { $0.kind != .parent })
    }
}
