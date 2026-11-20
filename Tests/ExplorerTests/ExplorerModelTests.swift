import XCTest
import ExplorerCore
@testable import Explorer

@MainActor
final class ExplorerModelTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplorerModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let suiteName = "ExplorerModelTests.\(UUID().uuidString)"
        defaultsSuiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let root {
            try? FileManager.default.removeItem(at: root)
        }
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        root = nil
        defaults = nil
        defaultsSuiteName = nil
    }

    func testNewFolderIsCreatedAsynchronouslyInCurrentDirectory() async throws {
        let model = makeModel()

        model.beginNewFolder(in: root)
        await waitUntil { model.nameEditor != nil }
        XCTAssertEqual(model.nameEditor?.directory, root)

        model.submitNameEditor("UI Created")
        let destination = root.appendingPathComponent("UI Created", isDirectory: true)
        await waitUntil {
            FileManager.default.fileExists(atPath: destination.path) && model.nameEditor == nil
        }

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCancelledNewFolderSubmissionStillReconcilesCreation() async throws {
        let model = makeModel()
        model.beginNewFolder(in: root)
        await waitUntil { model.nameEditor != nil }

        model.submitNameEditor("Cancelled Creation")
        model.cancelNameEditor()

        let destination = root.appendingPathComponent("Cancelled Creation", isDirectory: true)
        await waitUntil {
            FileManager.default.fileExists(atPath: destination.path)
                && model.undoTitle == "New Folder"
                && model.displayedItems.contains { $0.url.standardizedFileURL == destination }
        }

        XCTAssertNil(model.nameEditor)
        XCTAssertTrue(model.canUndoFileOperation)
        XCTAssertEqual(model.status?.text, "Created folder “Cancelled Creation”")
    }

    func testNewFolderInNonCurrentTreeDirectoryDoesNotNavigate() async throws {
        let current = root.appendingPathComponent("Current", isDirectory: true)
        let target = root.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let model = makeModel(startURL: current)

        model.beginNewFolder(in: target)
        await waitUntil { model.nameEditor != nil }
        model.submitNameEditor("Created Elsewhere")

        let destination = target.appendingPathComponent("Created Elsewhere", isDirectory: true)
        await waitUntil { FileManager.default.fileExists(atPath: destination.path) }
        XCTAssertEqual(model.currentURL, current)
        XCTAssertFalse(FileManager.default.fileExists(atPath: current.appendingPathComponent("Created Elsewhere").path))
    }

    func testLatestNavigationWinsWhenRequestsOverlap() async throws {
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        try Data().write(to: second.appendingPathComponent("second.txt"))
        let model = makeModel()

        model.navigate(to: first)
        model.navigate(to: second)

        await waitUntil { model.currentURL == second && !model.isLoading }
        XCTAssertEqual(model.displayedItems.map(\.name), ["second.txt"])
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.currentURL, second)
    }

    func testFailedTabRestorePreservesCurrentHistoryAndViewState() async throws {
        let current = root.appendingPathComponent("Current", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: false)
        let model = makeModel()
        model.navigate(to: current)
        await waitUntil { model.currentURL == current && !model.isLoading }
        model.setSort(field: .dateModified, ascending: false)
        model.setViewMode(.gallery)
        model.setFilter("Keep this filter")
        let original = model.captureTabState()

        let missing = root.appendingPathComponent("Missing", isDirectory: true)
        let unavailable = ExplorerTabState(
            path: missing.path,
            history: [root.path, current.path, missing.path],
            historyIndex: 2,
            sortField: "size",
            sortAscending: true,
            showHidden: !original.showHidden,
            filterText: "Unavailable filter",
            viewMode: ViewMode.details.rawValue,
            selection: ["missing"]
        )
        var result: Bool?
        model.restoreTabState(unavailable) { result = $0 }

        await waitUntil { result != nil }
        XCTAssertEqual(result, false)
        XCTAssertEqual(model.captureTabState(), original)
    }

    func testPropertiesMenuAllowsMultipleSelectionButRenameDoesNot() {
        let model = makeModel()
        let actions = ExplorerMenuActions(model: model)
        let properties = NSMenuItem(
            title: "Properties",
            action: #selector(ExplorerMenuActions.properties(_:)),
            keyEquivalent: "i"
        )
        let rename = NSMenuItem(
            title: "Rename",
            action: #selector(ExplorerMenuActions.rename(_:)),
            keyEquivalent: ""
        )

        model.selection = ["first", "second"]
        XCTAssertTrue(actions.validateMenuItem(properties))
        XCTAssertFalse(actions.validateMenuItem(rename))

        model.selection = ["first"]
        XCTAssertTrue(actions.validateMenuItem(properties))
        XCTAssertTrue(actions.validateMenuItem(rename))

        model.selection = []
        XCTAssertFalse(actions.validateMenuItem(properties))
        XCTAssertFalse(actions.validateMenuItem(rename))
    }

    func testInjectedDefaultsSupplyAndPersistPreferences() {
        defaults.set("dateModified", forKey: "Explorer.sortField")
        let model = makeModel()
        XCTAssertEqual(model.sortField, .dateModified)

        model.setViewMode(.gallery)
        XCTAssertEqual(defaults.string(forKey: "UUExplorer.viewMode"), ViewMode.gallery.rawValue)
    }

    func testPropertiesOpensOneAggregateWindowForMultipleFolders() async throws {
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        let model = makeModel()
        model.navigate(to: root)
        await waitUntil { model.displayedItems.count == 2 && !model.isLoading }
        model.selection = Set(model.displayedItems.map(\.id))

        model.showProperties()
        await waitUntil {
            NSApp.windows.contains { $0.title == "2 Items Properties" }
        }

        XCTAssertFalse(NSApp.windows.contains { $0.title == "First Properties" })
        XCTAssertFalse(NSApp.windows.contains { $0.title == "Second Properties" })
        for window in NSApp.windows where window.title == "2 Items Properties" {
            window.close()
        }
    }

    func testSelectionPropertiesCalculatesCombinedTotals() async throws {
        let first = root.appendingPathComponent("First", isDirectory: true)
        let second = root.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        try Data(repeating: 1, count: 3).write(to: first.appendingPathComponent("one.txt"))
        try Data(repeating: 2, count: 5).write(to: second.appendingPathComponent("two.txt"))
        let model = SelectionPropertiesModel(urls: [first, second])

        model.calculateTotals()
        await waitUntil { model.statistics.isComplete && !model.calculationTaskActive }

        XCTAssertEqual(model.statistics.logicalBytes, 8)
        XCTAssertEqual(model.statistics.fileCount, 2)
        XCTAssertEqual(model.statistics.folderCount, 0)
        XCTAssertEqual(model.completedRoots, 2)
        model.cancel()
    }

    func testSmallListFilteringRemainsSynchronous() async throws {
        try Data().write(to: root.appendingPathComponent("alpha.txt"))
        try Data().write(to: root.appendingPathComponent("beta.txt"))
        let model = makeModel()
        model.navigate(to: root)
        await waitUntil { model.displayedItems.count == 2 && !model.isLoading }

        model.setFilter("alpha")

        XCTAssertEqual(model.displayedItems.map(\.name), ["alpha.txt"])
    }

    func testLargeListFilteringPublishesLatestSortedResultAndVisibleSelection() async throws {
        for index in 1...300 {
            try Data().write(to: root.appendingPathComponent("item \(index).txt"))
        }
        let model = makeModel()
        model.navigate(to: root)
        await waitUntil(timeout: 10) { model.displayedItems.count == 300 && !model.isLoading }
        let selectedID = try XCTUnwrap(model.items.first(where: { $0.name == "item 2.txt" })?.id)
        let removedID = try XCTUnwrap(model.items.first(where: { $0.name == "item 3.txt" })?.id)
        model.selection = [selectedID, removedID]

        model.setFilter("item")
        model.setFilter("item 2")

        let expected = model.items
            .filter { $0.name.localizedCaseInsensitiveContains("item 2") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        await waitUntil(timeout: 10) {
            model.displayedItems.count == expected.count
                && model.displayedItems.allSatisfy { $0.name.localizedCaseInsensitiveContains("item 2") }
        }
        XCTAssertEqual(model.displayedItems.map(\.id), expected.map(\.id))
        XCTAssertEqual(model.selection, [selectedID])

        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.displayedItems.map(\.id), expected.map(\.id))
    }

    func testLargeListMetadataReloadAdvancesRevisionWithUnchangedIDs() async throws {
        for index in 1...300 {
            try Data().write(to: root.appendingPathComponent("item \(index).txt"))
        }
        let model = makeModel()
        model.navigate(to: root)
        await waitUntil(timeout: 10) { model.displayedItems.count == 300 && !model.isLoading }
        let target = root.appendingPathComponent("item 2.txt")
        let originalIDs = model.displayedItems.map(\.id)
        let originalRevision = model.displayedItemsRevision
        let modified = Date(timeIntervalSince1970: 1_650_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: target.path)

        model.reload()
        await waitUntil(timeout: 10) {
            model.displayedItemsRevision > originalRevision && !model.isLoading
        }

        XCTAssertEqual(model.displayedItems.map(\.id), originalIDs)
        let refreshedDate = try XCTUnwrap(
            model.displayedItems.first(where: { $0.name == "item 2.txt" })?.dateModified?.timeIntervalSince1970
        )
        XCTAssertEqual(refreshedDate, modified.timeIntervalSince1970, accuracy: 1)
    }

    func testRecursiveSearchPublishesFinalCoalescedResults() async throws {
        for index in 1...300 {
            try Data().write(to: root.appendingPathComponent("match \(index).txt"))
        }
        let model = makeModel()
        model.navigate(to: root)
        await waitUntil(timeout: 10) { model.displayedItems.count == 300 && !model.isLoading }
        model.setSearchScope(.recursive)

        model.setFilter("match")

        await waitUntil(timeout: 10) { !model.isSearching && model.displayedItems.count == 300 }
        XCTAssertEqual(model.searchScanned, 300)
        XCTAssertEqual(model.displayedItems.map(\.id), FileSorter.sorted(model.items, by: .name, ascending: true).map(\.id))
    }

    func testExtractHereUsesAvailableTopLevelFolderAndPreservesUndo() async throws {
        let source = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("contents".utf8).write(to: source.appendingPathComponent("file.txt"))
        let archive = root.appendingPathComponent("Project.zip")
        try ArchiveService.compress(source, to: archive)
        try FileManager.default.removeItem(at: source)
        let listedArchive = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).first(where: { $0.lastPathComponent == archive.lastPathComponent }))
        let model = makeModel(startURL: listedArchive.deletingLastPathComponent())

        model.extractHere(listedArchive)
        XCTAssertTrue(model.operations.operations.isEmpty)

        let extracted = source.appendingPathComponent("file.txt")
        await waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: extracted.path)
                && model.undoTitle == "Extract"
                && model.displayedItems.contains(where: { $0.name == "Project" })
        }
        let selectedID = try XCTUnwrap(model.displayedItems.first(where: { $0.name == "Project" })?.id)
        await waitUntil { model.selection == [selectedID] }
        XCTAssertEqual(model.status?.text, "Extracted “Project.zip”")
    }

    func testOverlappingExtractHereCallsOwnDistinctFolders() async throws {
        let source = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data("contents".utf8).write(to: source.appendingPathComponent("file.txt"))
        let archive = root.appendingPathComponent("Project.zip")
        try ArchiveService.compress(source, to: archive)
        try FileManager.default.removeItem(at: source)
        let listedArchive = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).first(where: { $0.lastPathComponent == archive.lastPathComponent }))
        let model = makeModel(startURL: listedArchive.deletingLastPathComponent())

        model.extractHere(listedArchive)
        model.extractHere(listedArchive)

        let firstDestination = source
        let secondDestination = root.appendingPathComponent("Project 2", isDirectory: true)
        let firstExtracted = firstDestination.appendingPathComponent("file.txt")
        let secondExtracted = secondDestination
            .appendingPathComponent("Project", isDirectory: true)
            .appendingPathComponent("file.txt")
        await waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: firstExtracted.path)
                && FileManager.default.fileExists(atPath: secondExtracted.path)
                && model.undoTitle == "Extract"
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstExtracted.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: secondExtracted.path))
        XCTAssertEqual(model.status?.text, "Extracted “Project.zip”")
        XCTAssertEqual(model.undoTitle, "Extract")
    }

    func testExtractHereCreatesUniqueWrapperForSingleFileArchive() async throws {
        let source = root.appendingPathComponent("note.txt")
        try Data("contents".utf8).write(to: source)
        let archive = root.appendingPathComponent("Bundle.zip")
        try ArchiveService.compress(source, to: archive)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Bundle", isDirectory: true),
            withIntermediateDirectories: false
        )
        let listedArchive = try XCTUnwrap(FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).first(where: { $0.lastPathComponent == archive.lastPathComponent }))
        let model = makeModel(startURL: listedArchive.deletingLastPathComponent())

        model.extractHere(listedArchive)

        let wrapper = root.appendingPathComponent("Bundle 2", isDirectory: true)
        let extracted = wrapper.appendingPathComponent("note.txt")
        await waitUntil(timeout: 10) {
            FileManager.default.fileExists(atPath: extracted.path)
                && model.undoTitle == "Extract"
                && model.displayedItems.contains(where: { $0.name == "Bundle 2" })
        }
        let selectedID = try XCTUnwrap(model.displayedItems.first(where: { $0.name == "Bundle 2" })?.id)
        await waitUntil { model.selection == [selectedID] }
        XCTAssertEqual(model.status?.text, "Extracted “Bundle.zip”")
    }

    private func makeModel(startURL: URL? = nil) -> ExplorerModel {
        ExplorerModel(startURL: startURL ?? root, defaults: defaults)
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "Condition was not met before timeout")
    }
}
