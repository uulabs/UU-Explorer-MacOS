import AppKit
import Combine
import ExplorerCore

private struct FileUndoRecord {
    let title: String
    let undo: () throws -> Void
    let redo: () throws -> Void
}

private final class TrashUndoState {
    var pairs: [(original: URL, trash: URL)]

    init(pairs: [(original: URL, trash: URL)]) {
        self.pairs = pairs
    }
}

struct TreeRoot: Identifiable, Hashable {
    let url: URL
    let name: String
    let isInternal: Bool

    var id: String { url.path }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case details
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .details: return "Details"
        case .gallery: return "Gallery"
        }
    }

    var symbol: String {
        switch self {
        case .details: return "list.bullet"
        case .gallery: return "square.grid.2x2"
        }
    }
}

enum SearchScope: String, Codable, CaseIterable, Identifiable {
    case folder
    case recursive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folder: return "This Folder"
        case .recursive: return "Include Subfolders"
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .recursive: return "arrow.triangle.branch"
        }
    }
}

struct OpenWithApplication: Identifiable {
    let url: URL

    var id: String { url.path }
    var name: String { FileManager.default.displayName(atPath: url.path) }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

struct EncryptedZipRequest: Identifiable {
    let id = UUID()
    let source: URL
    let target: URL
}

struct TreeRevealRequest: Equatable {
    let id = UUID()
    let path: String
}

struct BatchRenameSession: Identifiable {
    let id = UUID()
    let items: [FileItem]
}

struct SavedSearch: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var rootPath: String
    var query: String
    var scope: SearchScope
}

struct ExplorerStatus: Identifiable, Equatable {
    enum Kind: Equatable {
        case info
        case error
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

struct NameEditor: Identifiable {
    enum Mode: Equatable {
        case rename(URL)
        case newFolder(URL)
        case newFile(URL)
    }

    let id = UUID()
    let mode: Mode
    var text: String
    var error: String?

    var directory: URL {
        switch mode {
        case .rename(let url):
            return url.deletingLastPathComponent()
        case .newFolder(let url), .newFile(let url):
            return url
        }
    }

    var title: String {
        switch mode {
        case .rename: return "Rename"
        case .newFolder: return "New Folder"
        case .newFile: return "New File"
        }
    }

    var confirmLabel: String {
        switch mode {
        case .rename: return "Rename"
        case .newFolder, .newFile: return "Create"
        }
    }
}

@MainActor
final class ExplorerModel: ObservableObject {
    // MARK: Published state

    @Published private(set) var currentURL: URL
    @Published private(set) var currentFolderName: String
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var displayedItems: [FileItem] = []
    @Published var selection: Set<String> = []
    @Published private(set) var sortField: SortField
    @Published private(set) var sortAscending: Bool
    @Published private(set) var showHidden: Bool
    @Published private(set) var filterText: String = ""
    @Published var isEditingPath = false
    @Published var pathDraft = ""
    @Published private(set) var pathError = false
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var status: ExplorerStatus?
    @Published private(set) var volume: VolumeInfo?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var treeRoots: [TreeRoot] = []
    @Published private(set) var treeChildren: [String: [DirectoryEntry]] = [:]
    @Published private(set) var expandedPaths: Set<String> = []
    @Published private(set) var treeRevealRequest: TreeRevealRequest?
    @Published private(set) var treeLoading: Set<String> = []
    @Published private(set) var isSidebarVisible: Bool
    @Published private(set) var sidebarWidth: CGFloat
    @Published private(set) var viewMode: ViewMode
    @Published private(set) var galleryThumbnailSize: CGFloat
    @Published private(set) var favorites: [URL]
    @Published private(set) var isPreviewPaneVisible: Bool
    @Published private(set) var searchScope: SearchScope
    @Published private(set) var isSearching = false
    @Published private(set) var savedSearches: [SavedSearch]
    @Published private(set) var networkLocations: [NetworkLocation]
    @Published var batchRename: BatchRenameSession?
    @Published var encryptedZip: EncryptedZipRequest?
    @Published private(set) var folderSizes: [String: FolderSize] = [:]
    @Published private(set) var calculatingFolderPaths: Set<String> = []
    @Published private(set) var isCalculatingFolderSizes = false
    @Published private(set) var folderSizeDone = 0
    @Published private(set) var folderSizeTotal = 0
    @Published private(set) var storageFolderSize: FolderSize?
    @Published private(set) var isCalculatingStorageSize = false
    @Published var isShowingStorageUsage = false
    @Published var isCommandPaletteVisible = false
    @Published var nameEditor: NameEditor?

    // MARK: Navigation state

    let home: URL
    private let initialURL: URL
    private var history: [URL]
    private var historyIndex = 0
    private var loadGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchResults: [FileItem] = []
    private var searchGeneration = 0
    private var folderSizeTask: Task<Void, Never>?
    private var folderSizeWorker: Task<FolderSize, Never>?
    private var folderSizeGeneration = 0
    private var storageSizeTask: Task<Void, Never>?
    private var storageSizeWorker: Task<FolderSize, Never>?
    private var storageSizeGeneration = 0
    private var sharingPicker: NSSharingServicePicker?
    private var pendingSelection: Set<String>?
    private let defaults = UserDefaults.standard

    private static let cutPasteboardType = NSPasteboard.PasteboardType("com.uulabs.explorer.cut-urls")

    let operations = FileOperationQueue()
    var openInNewTabHandler: ((URL) -> Void)?

    @Published private(set) var undoTitle: String?
    @Published private(set) var redoTitle: String?
    private var undoStack: [FileUndoRecord] = []
    private var redoStack: [FileUndoRecord] = []
    private var undoTask: Task<Void, Never>?

    init(startURL: URL? = nil) {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        self.home = homeURL
        let start = (startURL ?? homeURL).standardizedFileURL
        self.initialURL = start
        self.currentURL = start
        self.history = [start]

        let storedSort = defaults.string(forKey: "Explorer.sortField").flatMap(SortField.init(rawValue:)) ?? .name
        self.sortField = storedSort
        self.sortAscending = defaults.object(forKey: "Explorer.sortAscending") as? Bool ?? true
        self.showHidden = defaults.bool(forKey: "Explorer.showHidden")
        self.isSidebarVisible = defaults.object(forKey: "Explorer.sidebarVisible") as? Bool ?? true
        let storedWidth = defaults.object(forKey: "Explorer.sidebarWidth") as? Double ?? 236
        self.sidebarWidth = CGFloat(min(max(storedWidth, 190), 420))
        self.viewMode = defaults.string(forKey: "UUExplorer.viewMode").flatMap(ViewMode.init(rawValue:)) ?? .details
        let storedThumbnailSize = defaults.object(forKey: "UUExplorer.galleryThumbnailSize") as? Double ?? 146
        self.galleryThumbnailSize = CGFloat(min(max(storedThumbnailSize, 110), 220))
        self.isPreviewPaneVisible = defaults.bool(forKey: "UUExplorer.previewPane")
        self.searchScope = defaults.string(forKey: "UUExplorer.searchScope").flatMap(SearchScope.init(rawValue:)) ?? .folder
        if let data = defaults.data(forKey: "UUExplorer.savedSearches.v1"),
           let decoded = try? JSONDecoder().decode([SavedSearch].self, from: data) {
            self.savedSearches = decoded
        } else {
            self.savedSearches = []
        }
        if let data = defaults.data(forKey: "UUExplorer.networkLocations.v1"),
           let decoded = try? JSONDecoder().decode([NetworkLocation].self, from: data) {
            self.networkLocations = decoded
        } else {
            self.networkLocations = []
        }
        let storedFavorites = defaults.array(forKey: "UUExplorer.favorites.v1") as? [String] ?? []
        self.favorites = storedFavorites
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .reduce(into: [URL]()) { result, url in
                if !result.contains(where: { $0.path == url.path }) { result.append(url) }
            }

        if start.path == "/" {
            self.currentFolderName = FileSystemService.volumeInfo(for: start)?.name ?? "Macintosh HD"
        } else {
            let name = FileManager.default.displayName(atPath: start.path)
            self.currentFolderName = name.isEmpty ? start.lastPathComponent : name
        }
        self.volume = FileSystemService.volumeInfo(for: start)
    }

    // MARK: Startup

    func start() {
        treeRoots = FileSystemService.mountedVolumes().map {
            TreeRoot(url: $0.url, name: $0.name, isInternal: $0.isInternal)
        }
        if treeRoots.isEmpty {
            treeRoots = [TreeRoot(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", isInternal: true)]
        }

        let startDirectory = FileSystemService.directoryExists(at: initialURL) ? initialURL : home
        if startDirectory.path != initialURL.path {
            history = [startDirectory]
            historyIndex = 0
        }
        expandedPaths.insert("/")
        Task { await loadTreeChildren(path: "/") }
        openDirectory(startDirectory, pushHistory: false, selecting: nil)
    }

    // MARK: Derived state

    var selectedItems: [FileItem] {
        displayedItems.filter { selection.contains($0.id) }
    }

    var selectedByteCount: Int64 {
        selectedItems.reduce(into: Int64(0)) { total, item in
            if !item.isDirectory { total += item.byteSize ?? 0 }
        }
    }

    var selectedFileCount: Int {
        selectedItems.filter { !$0.isDirectory }.count
    }

    var selectedFolderCount: Int {
        selectedItems.filter(\.isDirectory).count
    }

    var breadcrumbVolumeRoot: URL {
        volume?.rootURL ?? URL(fileURLWithPath: "/")
    }

    var breadcrumbVolumeName: String {
        volume?.name ?? "Macintosh HD"
    }

    var isFiltering: Bool { !filterText.isEmpty }
    var isRecursiveSearchActive: Bool { searchScope == .recursive && !filterText.isEmpty }

    // MARK: Navigation

    func navigate(to url: URL) {
        openDirectory(url, pushHistory: true, selecting: nil)
    }

    /// Browse external folders; reveal files without launching their associated app.
    func openExternal(_ urls: [URL], reveal: Bool) {
        let localURLs = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard let first = localURLs.first else { return }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory) else {
            openDirectory(first, pushHistory: true, selecting: nil)
            return
        }
        if isDirectory.boolValue && !reveal {
            openDirectory(first, pushHistory: true, selecting: nil)
            return
        }
        let parent = first.deletingLastPathComponent()
        let siblings = localURLs.filter { $0.deletingLastPathComponent() == parent }
        // A hidden target must be visible to be selected. This does not persist the setting.
        if siblings.contains(where: { $0.lastPathComponent.hasPrefix(".") ||
            (try? $0.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true }) {
            showHidden = true
        }
        openDirectory(parent, pushHistory: true, selecting: Set(siblings.map(\.path)))
        if siblings.count != localURLs.count {
            showStatus("Showing items in the first requested folder.")
        }
    }

    func goBack() {
        guard canGoBack, historyIndex > 0 else { return }
        historyIndex -= 1
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < history.count - 1
        openDirectory(history[historyIndex], pushHistory: false, selecting: nil)
    }

    func goForward() {
        guard canGoForward, historyIndex < history.count - 1 else { return }
        historyIndex += 1
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < history.count - 1
        openDirectory(history[historyIndex], pushHistory: false, selecting: nil)
    }

    func goUp() {
        guard let parent = PathTools.parent(of: currentURL) else { return }
        openDirectory(parent, pushHistory: true, selecting: [currentURL.path])
    }

    func goHome() {
        openDirectory(home, pushHistory: true, selecting: nil)
    }

    func go(to directory: URL) {
        openDirectory(directory, pushHistory: true, selecting: nil)
    }

    func refresh() {
        reload(preserveSelection: true)
        invalidateTree(currentURL)
        if isRecursiveSearchActive {
            scheduleRecursiveSearch()
        }
    }

    func open(_ item: FileItem) {
        if item.isDirectory && !item.isPackage {
            openDirectory(item.url, pushHistory: true, selecting: nil)
        } else if ArchiveService.isArchive(item.url) {
            extractHere(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openSelectedItems() {
        let selected = selectedItems
        guard let first = selected.first else { return }
        if selected.count == 1 {
            open(first)
            return
        }
        for item in selected where !item.isDirectory || item.isPackage {
            open(item)
        }
    }

    // MARK: Path editing

    func beginPathEditing() {
        pathDraft = currentURL.path
        pathError = false
        isEditingPath = true
    }

    func updatePathDraft(_ value: String) {
        pathDraft = value
        if pathError {
            pathError = false
        }
    }

    func cancelPathEditing() {
        isEditingPath = false
        pathError = false
    }

    @discardableResult
    func commitPath() -> Bool {
        guard let url = PathTools.expand(pathDraft, relativeTo: currentURL, home: home) else {
            pathError = true
            showStatus("Enter a valid path.", kind: .error)
            return false
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            pathError = true
            showStatus("The path “\(pathDraft)” can’t be found.", kind: .error)
            return false
        }

        isEditingPath = false
        pathError = false
        openDirectory(url, pushHistory: true, selecting: nil)
        return true
    }

    func suggestPaths() -> [PathSuggestion] {
        PathCompleter.suggestions(for: pathDraft, base: currentURL, home: home)
    }

    // MARK: Filtering and sorting

    func setFilter(_ text: String) {
        guard text != filterText else { return }
        filterText = text

        if text.isEmpty {
            cancelRecursiveSearch()
            rebuildVisibleItems()
        } else if searchScope == .recursive {
            scheduleRecursiveSearch()
        } else {
            cancelRecursiveSearch()
            rebuildVisibleItems()
        }
    }

    func setSearchScope(_ scope: SearchScope) {
        guard scope != searchScope else { return }
        searchScope = scope
        defaults.set(scope.rawValue, forKey: "UUExplorer.searchScope")

        if filterText.isEmpty {
            cancelRecursiveSearch()
            rebuildVisibleItems()
        } else if scope == .recursive {
            scheduleRecursiveSearch()
        } else {
            cancelRecursiveSearch()
            rebuildVisibleItems()
        }
    }

    func saveCurrentSearch() {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let root = currentURL.standardizedFileURL
        let name = "\(query) in \(currentFolderName)"
        if let index = savedSearches.firstIndex(where: {
            $0.rootPath == root.path && $0.query == query && $0.scope == searchScope
        }) {
            savedSearches[index].name = name
        } else {
            savedSearches.append(
                SavedSearch(
                    id: UUID(),
                    name: name,
                    rootPath: root.path,
                    query: query,
                    scope: searchScope
                )
            )
        }
        persistSavedSearches()
        showStatus("Saved search")
    }

    func runSavedSearch(_ search: SavedSearch) {
        let root = URL(fileURLWithPath: search.rootPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showStatus("The saved search folder no longer exists.", kind: .error)
            return
        }
        searchScope = search.scope
        openDirectory(root, pushHistory: true, selecting: nil)
        filterText = search.query
        if search.scope == .recursive {
            scheduleRecursiveSearch()
        } else {
            rebuildVisibleItems()
        }
    }

    func removeSavedSearch(_ search: SavedSearch) {
        savedSearches.removeAll { $0.id == search.id }
        persistSavedSearches()
    }

    private func persistSavedSearches() {
        guard let data = try? JSONEncoder().encode(savedSearches) else { return }
        defaults.set(data, forKey: "UUExplorer.savedSearches.v1")
    }

    private func scheduleRecursiveSearch() {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let root = currentURL.standardizedFileURL
        let query = filterText
        let hidden = showHidden

        isSearching = true
        searchResults = []
        displayedItems = []
        selection = []

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard let self, !Task.isCancelled, generation == self.searchGeneration else { return }
            let results = await Task.detached(priority: .userInitiated) {
                FileSystemService.recursiveSearch(
                    at: root,
                    matching: query,
                    includeHidden: hidden
                )
            }.value
            guard !Task.isCancelled, generation == self.searchGeneration else { return }
            self.searchResults = results
            self.isSearching = false
            self.rebuildVisibleItems()
            self.showStatus(
                results.isEmpty
                    ? "No matches for “\(query)”"
                    : "\(results.count) result\(results.count == 1 ? "" : "s") for “\(query)”"
            )
        }
    }

    private func cancelRecursiveSearch() {
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchResults = []
    }

    func setSort(field: SortField, ascending: Bool) {
        guard field != sortField || ascending != sortAscending else { return }
        sortField = field
        sortAscending = ascending
        defaults.set(field.rawValue, forKey: "Explorer.sortField")
        defaults.set(ascending, forKey: "Explorer.sortAscending")
        rebuildVisibleItems()
    }

    func toggleHiddenFiles() {
        showHidden.toggle()
        defaults.set(showHidden, forKey: "Explorer.showHidden")
        treeChildren.removeAll()
        reload(preserveSelection: true)
        if isRecursiveSearchActive {
            scheduleRecursiveSearch()
        }
        Task {
            for path in expandedPaths {
                await loadTreeChildren(path: path, force: true)
            }
        }
    }

    func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible)
    }

    func setSidebarVisible(_ visible: Bool, persist: Bool = true) {
        isSidebarVisible = visible
        if persist {
            defaults.set(isSidebarVisible, forKey: "Explorer.sidebarVisible")
        }
    }

    func togglePreviewPane() {
        isPreviewPaneVisible.toggle()
        defaults.set(isPreviewPaneVisible, forKey: "UUExplorer.previewPane")
    }

    func setSidebarWidth(_ width: CGFloat) {
        let clamped = min(max(width, 190), 420)
        guard clamped != sidebarWidth else { return }
        sidebarWidth = clamped
        defaults.set(Double(clamped), forKey: "Explorer.sidebarWidth")
    }

    func setViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        defaults.set(mode.rawValue, forKey: "UUExplorer.viewMode")
    }

    // MARK: Tabs

    func captureTabState() -> ExplorerTabState {
        ExplorerTabState(
            path: currentURL.path,
            history: history.map(\.path),
            historyIndex: historyIndex,
            sortField: sortField.rawValue,
            sortAscending: sortAscending,
            showHidden: showHidden,
            filterText: filterText,
            viewMode: viewMode.rawValue,
            selection: Array(selection)
        )
    }

    func restoreTabState(_ state: ExplorerTabState) {
        let url = URL(fileURLWithPath: state.path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showStatus("“\(state.path)” can’t be found.", kind: .error)
            return
        }

        nameEditor = nil
        isEditingPath = false
        pathDraft = ""
        pathError = false
        sortField = SortField(rawValue: state.sortField) ?? sortField
        sortAscending = state.sortAscending
        showHidden = state.showHidden
        viewMode = ViewMode(rawValue: state.viewMode) ?? viewMode

        var restoredHistory = state.history.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if restoredHistory.isEmpty {
            restoredHistory = [url]
        }
        history = restoredHistory
        historyIndex = min(max(state.historyIndex, 0), restoredHistory.count - 1)
        canGoBack = historyIndex > 0
        canGoForward = historyIndex < restoredHistory.count - 1

        let savedFilter = state.filterText
        openDirectory(url, pushHistory: false, selecting: Set(state.selection))
        if !savedFilter.isEmpty {
            filterText = savedFilter
            rebuildVisibleItems()
        }
    }

    func openInNewTab(_ url: URL) {
        openInNewTabHandler?(url.standardizedFileURL)
    }

    func setGalleryThumbnailSize(_ size: CGFloat) {
        let clamped = min(max(size, 110), 220)
        guard abs(clamped - galleryThumbnailSize) > 0.5 else { return }
        galleryThumbnailSize = clamped
        defaults.set(Double(clamped), forKey: "UUExplorer.galleryThumbnailSize")
    }

    func increaseGalleryThumbnailSize() {
        setGalleryThumbnailSize(galleryThumbnailSize + 16)
    }

    func decreaseGalleryThumbnailSize() {
        setGalleryThumbnailSize(galleryThumbnailSize - 16)
    }

    func moveGallerySelection(by offset: Int) {
        guard viewMode == .gallery, !displayedItems.isEmpty else { return }
        let ids = displayedItems.map(\.id)
        let currentIndex = selection.first.flatMap { ids.firstIndex(of: $0) }
        let targetIndex: Int
        if let currentIndex {
            targetIndex = min(max(currentIndex + offset, 0), ids.count - 1)
        } else {
            targetIndex = offset < 0 ? ids.count - 1 : 0
        }
        selection = [ids[targetIndex]]
    }

    // MARK: Favourites

    var currentFolderIsFavorite: Bool {
        isFavorite(currentURL)
    }

    func isFavorite(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return favorites.contains { $0.standardizedFileURL.path == path }
    }

    func toggleFavorite(_ url: URL) {
        let directory = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            showStatus("Only folders can be added to Favourites.", kind: .error)
            return
        }

        if let index = favorites.firstIndex(where: { $0.standardizedFileURL.path == directory.path }) {
            favorites.remove(at: index)
            showStatus("Removed from Favourites")
        } else {
            favorites.append(directory)
            showStatus("Added to Favourites")
        }
        defaults.set(favorites.map(\.path), forKey: "UUExplorer.favorites.v1")
    }

    func toggleCurrentFolderFavorite() {
        toggleFavorite(currentURL)
    }

    // MARK: Quick Look

    func quickLookSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        QuickLookController.shared.toggle(urls: urls)
    }

    // MARK: Archives

    var canCompressSelection: Bool {
        selectedItems.count == 1
    }

    var canExtractSelection: Bool {
        selectedItems.count == 1 && selectedItems.first.map { ArchiveService.isArchive($0.url) } == true
    }

    func compressSelection() {
        let selected = selectedItems
        guard selected.count == 1, let item = selected.first else {
            showStatus("Select one file or folder to compress.", kind: .error)
            return
        }

        let source = item.url
        let directory = currentURL
        let target = FileName.uniqueURL(
            in: directory,
            baseName: source.lastPathComponent,
            pathExtension: "zip"
        )
        operations.enqueueArchive(kind: .compress, source: source, destination: target) { [weak self] outcome in
            guard let self else { return }
            if !outcome.failures.isEmpty {
                self.showStatus(
                    "Couldn’t compress “\(source.lastPathComponent)”. \(outcome.failures[0])",
                    kind: .error
                )
                return
            }
            guard !outcome.cancelled else { return }
            self.invalidateTree(directory)
            self.reload(preserveSelection: false, selecting: [target.path])
            self.showStatus("Compressed “\(target.lastPathComponent)”")
            self.registerFileUndo(
                title: "Compress",
                undo: { _ = try TrashService.recycle(target) },
                redo: { try ArchiveService.compress(source, to: target) }
            )
        }
    }

    func extractSelectionHere() {
        let selected = selectedItems
        guard selected.count == 1, let item = selected.first, ArchiveService.isArchive(item.url) else {
            showStatus("Select a ZIP, TAR, TAR.GZ, RAR, or 7-Zip archive to extract.", kind: .error)
            return
        }
        extractHere(item.url)
    }

    func extractHere(_ archive: URL) {
        let parent = archive.deletingLastPathComponent().standardizedFileURL
        let stem = archiveStem(for: archive)
        let top = ArchiveService.topLevelDirectoryName(archive)
        let topURL = top.map { parent.appendingPathComponent($0) }

        let destination: URL
        let selection: URL?
        if let topURL, !FileManager.default.fileExists(atPath: topURL.path) {
            destination = parent
            selection = topURL
        } else {
            let wrapper = FileName.uniqueURL(in: parent, baseName: stem)
            do {
                try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: false)
            } catch {
                showStatus("Couldn’t create the extraction folder. \(error.localizedDescription)", kind: .error)
                return
            }
            destination = wrapper
            selection = wrapper
        }
        extract(archive, to: destination, selecting: selection)
    }

    private func archiveStem(for archive: URL) -> String {
        let name = archive.lastPathComponent
        let lower = name.lowercased()
        for suffix in [".tar.gz", ".tgz", ".zip", ".tar"] where lower.hasSuffix(suffix) {
            let stem = String(name.dropLast(suffix.count))
            return stem.isEmpty ? "Extracted" : stem
        }
        return archive.deletingPathExtension().lastPathComponent.isEmpty
            ? "Extracted"
            : archive.deletingPathExtension().lastPathComponent
    }

    func extractSelection() {
        let selected = selectedItems
        guard selected.count == 1, let item = selected.first, ArchiveService.isArchive(item.url) else {
            showStatus("Select a ZIP, TAR, TAR.GZ, RAR, or 7-Zip archive to extract.", kind: .error)
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Extract “\(item.name)”"
        panel.message = "Choose a folder for the extracted files."
        panel.prompt = "Extract"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL
        guard panel.runModal() == .OK, let destination = panel.url?.standardizedFileURL else { return }
        extract(item.url, to: destination)
    }

    func extract(_ archive: URL, to destination: URL, selecting selectedURL: URL? = nil) {
        let directory = destination.standardizedFileURL
        operations.enqueueArchive(kind: .extract, source: archive, destination: directory) { [weak self] outcome in
            guard let self else { return }
            if !outcome.failures.isEmpty {
                self.showStatus(
                    "Couldn’t extract “\(archive.lastPathComponent)”. \(outcome.failures[0])",
                    kind: .error
                )
                return
            }
            guard !outcome.cancelled else { return }

            let current = self.currentURL.standardizedFileURL
            if directory.path == current.path ||
                directory.deletingLastPathComponent().standardizedFileURL.path == current.path {
                self.reload(
                    preserveSelection: false,
                    selecting: selectedURL.map { Set([$0.path]) } ?? []
                )
            }
            self.invalidateTree(directory)
            self.showStatus("Extracted “\(archive.lastPathComponent)”")

            if let selectedURL {
                self.registerFileUndo(
                    title: "Extract",
                    undo: { _ = try TrashService.recycle(selectedURL) },
                    redo: {
                        if !FileManager.default.fileExists(atPath: directory.path) {
                            try FileManager.default.createDirectory(
                                at: directory,
                                withIntermediateDirectories: true
                            )
                        }
                        try ArchiveService.extract(archive, to: directory)
                    }
                )
            }
        }
    }

    func selectOnly(_ item: FileItem) {
        selection = [item.id]
    }

    func toggleSelection(_ item: FileItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func selectRange(in items: [FileItem], from anchorID: String, to item: FileItem) {
        guard let anchor = items.firstIndex(where: { $0.id == anchorID }),
              let target = items.firstIndex(where: { $0.id == item.id }) else {
            selection = [item.id]
            return
        }
        let range = anchor <= target ? anchor...target : target...anchor
        selection = Set(items[range].map(\.id))
    }

    // MARK: File actions

    func beginRenameSelected() {
        guard selectedItems.count == 1, let item = selectedItems.first else { return }
        nameEditor = NameEditor(mode: .rename(item.url), text: item.name, error: nil)
    }

    func beginNewFolder() {
        isEditingPath = false
        if !filterText.isEmpty { setFilter("") }
        let unique = FileName.uniqueURL(in: currentURL, baseName: "New Folder")
        nameEditor = NameEditor(mode: .newFolder(currentURL), text: unique.lastPathComponent, error: nil)
    }

    func beginNewFile() {
        isEditingPath = false
        if !filterText.isEmpty { setFilter("") }
        let unique = FileName.uniqueURL(in: currentURL, baseName: "New File", pathExtension: "txt")
        nameEditor = NameEditor(mode: .newFile(currentURL), text: unique.lastPathComponent, error: nil)
    }

    func beginBatchRename() {
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        batchRename = BatchRenameSession(items: selected)
    }

    func cancelBatchRename() {
        batchRename = nil
    }

    func applyBatchRename(_ previews: [BatchRenamePreview]) {
        let changes = previews.filter { $0.hasChange && $0.error == nil }
        guard !changes.isEmpty else {
            batchRename = nil
            return
        }

        var completed: [(source: URL, target: URL)] = []
        do {
            for preview in changes {
                let target = preview.targetURL
                guard !FileManager.default.fileExists(atPath: target.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try FileManager.default.moveItem(at: preview.sourceURL, to: target)
                completed.append((preview.sourceURL, target))
            }

            registerFileUndo(
                title: "Batch Rename",
                undo: {
                    for pair in completed.reversed() {
                        try FileManager.default.moveItem(at: pair.target, to: pair.source)
                    }
                },
                redo: {
                    for pair in completed {
                        try FileManager.default.moveItem(at: pair.source, to: pair.target)
                    }
                }
            )

            batchRename = nil
            invalidateTree(currentURL)
            reload(preserveSelection: false, selecting: Set(completed.map(\.target.path)))
            showStatus("Renamed \(completed.count) item\(completed.count == 1 ? "" : "s")")
        } catch {
            for pair in completed.reversed() {
                try? FileManager.default.moveItem(at: pair.target, to: pair.source)
            }
            showStatus("Couldn’t rename the batch: \(error.localizedDescription)", kind: .error)
        }
    }

    func submitNameEditor(_ rawName: String) {
        guard var editor = nameEditor else { return }
        let name = rawName

        if let validation = FileName.validationError(for: name) {
            editor.error = validation
            nameEditor = editor
            return
        }

        switch editor.mode {
        case .rename(let source):
            let destination = source.deletingLastPathComponent().appendingPathComponent(name)
            if destination.path == source.path {
                nameEditor = nil
                return
            }
            let destinationExists = FileManager.default.fileExists(atPath: destination.path)
            let caseOnlyRename = destination.path.lowercased() == source.path.lowercased()
            if destinationExists && !caseOnlyRename {
                editor.error = "An item named “\(name)” already exists."
                nameEditor = editor
                return
            }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                registerFileUndo(
                    title: "Rename",
                    undo: { try FileManager.default.moveItem(at: destination, to: source) },
                    redo: { try FileManager.default.moveItem(at: source, to: destination) }
                )
                forgetTreeSubtree(source.path)
                invalidateTree(source.deletingLastPathComponent())
                nameEditor = nil
                reload(preserveSelection: false, selecting: [destination.path])
                showStatus("Renamed to “\(name)”")
            } catch {
                editor.error = error.localizedDescription
                nameEditor = editor
            }

        case .newFolder(let directory):
            let destination = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                editor.error = "An item named “\(name)” already exists."
                nameEditor = editor
                return
            }
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                registerFileUndo(
                    title: "New Folder",
                    undo: { _ = try TrashService.recycle(destination) },
                    redo: { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false) }
                )
                invalidateTree(directory)
                nameEditor = nil
                reload(preserveSelection: false, selecting: [destination.path])
                showStatus("Created folder “\(name)”")
            } catch {
                editor.error = error.localizedDescription
                nameEditor = editor
            }

        case .newFile(let directory):
            let destination = directory.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                editor.error = "An item named “\(name)” already exists."
                nameEditor = editor
                return
            }
            do {
                try Data().write(to: destination, options: .withoutOverwriting)
                registerFileUndo(
                    title: "New File",
                    undo: { _ = try TrashService.recycle(destination) },
                    redo: { try Data().write(to: destination, options: .withoutOverwriting) }
                )
                nameEditor = nil
                reload(preserveSelection: false, selecting: [destination.path])
                showStatus("Created “\(name)”")
            } catch {
                editor.error = error.localizedDescription
                nameEditor = editor
            }
        }
    }

    func cancelNameEditor() {
        nameEditor = nil
    }

    func moveSelectionToTrash() {
        let itemsToTrash = selectedItems
        let urls = itemsToTrash.map(\.url)
        guard !urls.isEmpty else { return }

        Task {
            let outcome: ([(original: URL, trash: URL)], [String]) = await Task.detached(priority: .userInitiated) {
                var moved: [(original: URL, trash: URL)] = []
                var failures: [String] = []
                for url in urls {
                    do {
                        if let trashURL = try TrashService.recycle(url) {
                            moved.append((original: url, trash: trashURL))
                        }
                    } catch {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (moved, failures)
            }.value

            for item in itemsToTrash where outcome.0.contains(where: { $0.original.path == item.url.path }) {
                self.forgetTreeSubtree(item.url.path)
            }
            self.selection = []
            self.invalidateTree(self.currentURL)
            self.reload(preserveSelection: false)

            if !outcome.0.isEmpty {
                let state = TrashUndoState(pairs: outcome.0)
                self.registerFileUndo(
                    title: "Move to Trash",
                    undo: {
                        for pair in state.pairs.reversed() {
                            try FileManager.default.moveItem(at: pair.trash, to: pair.original)
                        }
                    },
                    redo: {
                        for index in state.pairs.indices {
                            let original = state.pairs[index].original
                            if let newTrash = try TrashService.recycle(original) {
                                state.pairs[index].trash = newTrash
                            }
                        }
                    }
                )
            }

            if outcome.1.isEmpty {
                let noun = outcome.0.count == 1 ? "item" : "items"
                self.showStatus("Moved \(outcome.0.count) \(noun) to Trash")
            } else {
                self.showStatus(
                    "Couldn’t move \(outcome.1.count) item\(outcome.1.count == 1 ? "" : "s") to Trash. \(outcome.1[0])",
                    kind: .error
                )
            }
        }
    }

    func showProperties() {
        guard let item = selectedItems.first, selection.count == 1 else { return }
        PropertiesWindowController.show(for: item.url)
    }

    func revealSelectionInFinder() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openInTerminal(_ directory: URL) {
        let target = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showStatus("Only folders can be opened in Terminal.", kind: .error)
            return
        }

        let candidates = [
            URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            URL(fileURLWithPath: "/Applications/Utilities/Terminal.app")
        ]
        guard let terminal = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            showStatus("Terminal.app couldn’t be found.", kind: .error)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [target],
            withApplicationAt: terminal,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.showStatus("Couldn’t open Terminal: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func openCurrentFolderInTerminal() {
        openInTerminal(currentURL)
    }

    func copySelectionPath() {
        let paths = selectedItems.map(\.url.path)
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        showStatus(paths.count == 1 ? "Copied path" : "Copied \(paths.count) paths")
    }

    func copySelectionToPasteboard(cut: Bool = false) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        if cut {
            pasteboard.setString(urls.map(\.path).joined(separator: "\n"), forType: Self.cutPasteboardType)
        }
        let verb = cut ? "Cut" : "Copied"
        showStatus("\(verb) \(urls.count) \(urls.count == 1 ? "item" : "items")")
    }

    var canPaste: Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    func pasteFiles(into explicitDestination: URL? = nil) {
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            showStatus("There’s nothing to paste.", kind: .error)
            return
        }

        let isCut = pasteboard.string(forType: Self.cutPasteboardType) != nil
        performTransfer(
            urls,
            to: explicitDestination ?? currentURL,
            isCut: isCut,
            successVerb: isCut ? "Moved" : "Pasted",
            clearCutPasteboard: isCut
        )
    }

    /// Used by drag-and-drop and the future operation queue. Copies keep the
    /// source name; moves remove it. Existing names never overwrite.
    func transfer(_ urls: [URL], to destination: URL, copy: Bool) {
        performTransfer(
            urls,
            to: destination,
            isCut: !copy,
            successVerb: copy ? "Copied" : "Moved",
            clearCutPasteboard: false
        )
    }

    private func performTransfer(
        _ urls: [URL],
        to requestedDestination: URL,
        isCut: Bool,
        successVerb: String,
        clearCutPasteboard: Bool
    ) {
        let destination = requestedDestination.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showStatus("The destination is no longer available.", kind: .error)
            return
        }

        let sources = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        guard !sources.isEmpty else { return }

        let selectsInCurrentFolder = destination.path == currentURL.standardizedFileURL.path
        operations.enqueueTransfer(
            sources: sources,
            destination: destination,
            isMove: isCut
        ) { [weak self] outcome in
            guard let self else { return }
            if clearCutPasteboard, isCut, outcome.failures.isEmpty, !outcome.cancelled {
                NSPasteboard.general.clearContents()
            }
            if !outcome.created.isEmpty {
                self.invalidateTree(destination)
                if isCut {
                    for source in sources {
                        self.invalidateTree(source.deletingLastPathComponent())
                    }
                }
                self.reload(
                    preserveSelection: false,
                    selecting: selectsInCurrentFolder ? Set(outcome.created.map(\.path)) : []
                )
            }

            if outcome.cancelled {
                self.showStatus("Transfer cancelled")
            } else if !outcome.failures.isEmpty {
                let action = isCut ? "move" : "copy"
                self.showStatus(
                    "Couldn’t \(action) \(outcome.failures.count) item\(outcome.failures.count == 1 ? "" : "s"). \(outcome.failures[0])",
                    kind: .error
                )
            } else if !outcome.created.isEmpty {
                self.showStatus("\(successVerb) \(outcome.created.count) \(outcome.created.count == 1 ? "item" : "items")")
            }
            if !outcome.cancelled {
                self.registerTransferUndo(isCut: isCut, pairs: outcome.pairs)
            }
        }
    }

    // MARK: Open With and sharing

    func openWithApplications(for url: URL) -> [OpenWithApplication] {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: url)
        var seenPaths = Set<String>()
        var seenNames = Set<String>()
        return apps
            .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
            .map(OpenWithApplication.init(url:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .filter { seenNames.insert($0.name).inserted }
            .prefix(20)
            .map { $0 }
    }

    func openSelection(with application: URL) {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: application,
            configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor [weak self] in
                self?.showStatus("Couldn’t open with app: \(error.localizedDescription)", kind: .error)
            }
        }
    }

    func shareSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty,
              let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingPicker = picker

        let mouse = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let anchor = contentView.bounds.contains(mouse)
            ? NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
            : NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }

    func duplicateSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }

        Task { [weak self] in
            let outcome: ([TransferPair], [String]) = await Task.detached(priority: .userInitiated) {
                var pairs: [TransferPair] = []
                var failures: [String] = []
                for source in urls {
                    do {
                        let parent = source.deletingLastPathComponent()
                        let target = FileName.uniqueDestination(for: source, in: parent, duplicate: true)
                        try FileManager.default.copyItem(at: source, to: target)
                        pairs.append(TransferPair(source: source, target: target))
                    } catch {
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (pairs, failures)
            }.value
            guard let self else { return }
            if !outcome.0.isEmpty {
                self.registerFileUndo(
                    title: "Duplicate",
                    undo: {
                        for pair in outcome.0.reversed() where FileManager.default.fileExists(atPath: pair.target.path) {
                            _ = try TrashService.recycle(pair.target)
                        }
                    },
                    redo: {
                        for pair in outcome.0 {
                            try FileManager.default.copyItem(at: pair.source, to: pair.target)
                        }
                    }
                )
                self.invalidateTree(self.currentURL)
                self.reload(preserveSelection: false, selecting: Set(outcome.0.map(\.target.path)))
            }
            if !outcome.1.isEmpty {
                self.showStatus("Couldn’t duplicate: \(outcome.1[0])", kind: .error)
            } else {
                self.showStatus("Duplicated \(outcome.0.count) item\(outcome.0.count == 1 ? "" : "s")")
            }
        }
    }

    func createLinkSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }

        Task { [weak self] in
            let outcome: ([TransferPair], [String]) = await Task.detached(priority: .userInitiated) {
                var pairs: [TransferPair] = []
                var failures: [String] = []
                for source in urls {
                    do {
                        let parent = source.deletingLastPathComponent()
                        let target = FileName.uniqueURL(
                            in: parent,
                            baseName: "\(source.lastPathComponent) link"
                        )
                        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
                        pairs.append(TransferPair(source: source, target: target))
                    } catch {
                        failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return (pairs, failures)
            }.value
            guard let self else { return }
            if !outcome.0.isEmpty {
                self.registerFileUndo(
                    title: "Create Link",
                    undo: {
                        for pair in outcome.0.reversed() where FileManager.default.fileExists(atPath: pair.target.path) {
                            _ = try TrashService.recycle(pair.target)
                        }
                    },
                    redo: {
                        for pair in outcome.0 {
                            try FileManager.default.createSymbolicLink(
                                at: pair.target,
                                withDestinationURL: pair.source
                            )
                        }
                    }
                )
                self.invalidateTree(self.currentURL)
                self.reload(preserveSelection: false, selecting: Set(outcome.0.map(\.target.path)))
            }
            if !outcome.1.isEmpty {
                self.showStatus("Couldn’t create link: \(outcome.1[0])", kind: .error)
            } else {
                self.showStatus("Created \(outcome.0.count) link\(outcome.0.count == 1 ? "" : "s")")
            }
        }
    }

    func toggleCommandPalette() {
        isCommandPaletteVisible.toggle()
    }

    func closeCommandPalette() {
        isCommandPaletteVisible = false
    }

    // MARK: Encrypted ZIP

    func beginEncryptedCompression() {
        let selected = selectedItems
        guard selected.count == 1, let item = selected.first else {
            showStatus("Select one file or folder to compress.", kind: .error)
            return
        }
        let target = FileName.uniqueURL(
            in: currentURL,
            baseName: item.url.lastPathComponent,
            pathExtension: "zip"
        )
        encryptedZip = EncryptedZipRequest(source: item.url, target: target)
    }

    func createEncryptedZip(password: String, request: EncryptedZipRequest) {
        encryptedZip = nil
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ArchiveService.compressEncrypted(request.source, to: request.target, password: password)
                }.value
                guard let self else { return }
                self.invalidateTree(self.currentURL)
                self.reload(preserveSelection: false, selecting: [request.target.path])
                self.showStatus("Created encrypted ZIP “\(request.target.lastPathComponent)”")
            } catch {
                self?.showStatus("Couldn’t create encrypted ZIP. \(error.localizedDescription)", kind: .error)
            }
        }
    }

    // MARK: Network locations

    func addNetworkLocation() {
        let alert = NSAlert()
        alert.messageText = "Add Network Location"
        alert.informativeText = "Enter an SMB, AFP, or NFS address. Credentials are handled by macOS."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let addressField = NSTextField(string: "smb://")
        addressField.placeholderString = "smb://server/share"
        addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Optional display name"
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Address:"), addressField],
            [NSTextField(labelWithString: "Name:"), nameField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        alert.accessoryView = grid

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = saveNetworkLocation(address: addressField.stringValue, name: nameField.stringValue)
    }

    @discardableResult
    func saveNetworkLocation(address: String, name: String = "") -> Bool {
        do {
            let location = try NetworkLocation.parse(address: address, name: name)
            if networkLocations.contains(where: {
                $0.urlString.caseInsensitiveCompare(location.urlString) == .orderedSame
            }) {
                showStatus("That network location is already saved.")
                return false
            }
            networkLocations.append(location)
            persistNetworkLocations()
            showStatus("Saved network location “\(location.name)”")
            return true
        } catch {
            showStatus(error.localizedDescription, kind: .error)
            return false
        }
    }

    func connectNetworkLocation(_ location: NetworkLocation) {
        guard let url = location.url else {
            showStatus("The network address is invalid.", kind: .error)
            return
        }
        NSWorkspace.shared.open(url)
        showStatus("Connecting to \(location.name)…")
    }

    func removeNetworkLocation(_ location: NetworkLocation) {
        networkLocations.removeAll { $0.id == location.id }
        persistNetworkLocations()
    }

    private func persistNetworkLocations() {
        guard let data = try? JSONEncoder().encode(networkLocations) else { return }
        defaults.set(data, forKey: "UUExplorer.networkLocations.v1")
    }

    // MARK: Folder sizes

    func calculateVisibleFolderSizes() {
        let directories = displayedItems
            .filter(\.isDirectory)
            .filter { folderSizes[$0.url.path] == nil }
            .map(\.url)
        guard !directories.isEmpty else {
            showStatus("Visible folders already have calculated sizes.")
            return
        }
        calculateFolderSizes(directories)
    }

    func calculateSelectedFolderSizes() {
        let directories = selectedItems.filter(\.isDirectory).map(\.url)
        guard !directories.isEmpty else {
            showStatus("Select a folder to calculate its size.", kind: .error)
            return
        }
        calculateFolderSizes(directories)
    }

    func calculateFolderSizes(_ urls: [URL]) {
        var seen = Set<String>()
        let directories = urls
            .map(\.standardizedFileURL)
            .filter { url in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { return false }
                return seen.insert(url.path).inserted
            }
        guard !directories.isEmpty else { return }

        cancelFolderSizeCalculation(announce: false)
        folderSizeGeneration &+= 1
        let generation = folderSizeGeneration
        folderSizeDone = 0
        folderSizeTotal = directories.count
        isCalculatingFolderSizes = true
        calculatingFolderPaths = Set(directories.map(\.path))
        let total = directories.count

        folderSizeTask = Task { [weak self] in
            guard let self else { return }
            for url in directories {
                if Task.isCancelled { break }
                let worker = Task.detached(priority: .utility) {
                    FolderSizeService.calculate(at: url) { Task.isCancelled }
                }
                self.folderSizeWorker = worker
                let size = await worker.value
                guard generation == self.folderSizeGeneration else { return }
                if Task.isCancelled { break }
                self.folderSizes[url.path] = size
                self.calculatingFolderPaths.remove(url.path)
                self.folderSizeDone += 1
            }
            guard generation == self.folderSizeGeneration else { return }
            self.folderSizeTask = nil
            self.folderSizeWorker = nil
            self.isCalculatingFolderSizes = false
            self.calculatingFolderPaths = []
            if Task.isCancelled {
                self.showStatus("Folder size calculation cancelled")
            } else {
                self.showStatus("Calculated \(total) folder size\(total == 1 ? "" : "s")")
            }
        }
    }

    func cancelFolderSizeCalculation() {
        cancelFolderSizeCalculation(announce: true)
    }

    private func cancelFolderSizeCalculation(announce: Bool) {
        let wasRunning = isCalculatingFolderSizes
        folderSizeGeneration &+= 1
        folderSizeTask?.cancel()
        folderSizeWorker?.cancel()
        folderSizeTask = nil
        folderSizeWorker = nil
        isCalculatingFolderSizes = false
        calculatingFolderPaths = []
        if announce, wasRunning {
            showStatus("Folder size calculation cancelled")
        }
    }

    // MARK: Storage usage

    func showStorageUsage() {
        isShowingStorageUsage = true
    }

    func hideStorageUsage() {
        isShowingStorageUsage = false
        storageSizeGeneration &+= 1
        storageSizeTask?.cancel()
        storageSizeWorker?.cancel()
        storageSizeTask = nil
        storageSizeWorker = nil
        isCalculatingStorageSize = false
    }

    func calculateStorageSize() {
        storageSizeGeneration &+= 1
        let generation = storageSizeGeneration
        storageSizeTask?.cancel()
        storageSizeWorker?.cancel()
        let root = currentURL.standardizedFileURL
        isCalculatingStorageSize = true
        storageFolderSize = nil

        storageSizeTask = Task { [weak self] in
            guard let self else { return }
            let worker = Task.detached(priority: .utility) {
                FolderSizeService.calculate(at: root) { Task.isCancelled }
            }
            self.storageSizeWorker = worker
            let size = await worker.value
            guard generation == self.storageSizeGeneration else { return }
            self.storageFolderSize = size
            self.storageSizeWorker = nil
            self.storageSizeTask = nil
            self.isCalculatingStorageSize = false
        }
    }

    // MARK: Undo

    var canUndoFileOperation: Bool { !undoStack.isEmpty && undoTask == nil }
    var canRedoFileOperation: Bool { !redoStack.isEmpty && undoTask == nil }

    func registerFileUndo(
        title: String,
        undo: @escaping () throws -> Void,
        redo: @escaping () throws -> Void
    ) {
        undoStack.append(FileUndoRecord(title: title, undo: undo, redo: redo))
        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
        redoStack.removeAll()
        updateUndoTitles()
    }

    func undoFileOperation() {
        performFileUndo(isRedo: false)
    }

    func redoFileOperation() {
        performFileUndo(isRedo: true)
    }

    private func performFileUndo(isRedo: Bool) {
        guard undoTask == nil else { return }
        let record: FileUndoRecord?
        if isRedo {
            record = redoStack.popLast()
        } else {
            record = undoStack.popLast()
        }
        guard let record else {
            updateUndoTitles()
            return
        }
        updateUndoTitles()
        undoTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached(priority: .userInitiated) {
                    if isRedo { try record.redo() } else { try record.undo() }
                }.value
                if isRedo {
                    self.undoStack.append(record)
                } else {
                    self.redoStack.append(record)
                }
                self.invalidateTree(self.currentURL)
                self.reload(preserveSelection: false)
                self.showStatus(isRedo ? "Redid \(record.title)" : "Undid \(record.title)")
            } catch {
                if isRedo {
                    self.redoStack.append(record)
                } else {
                    self.undoStack.append(record)
                }
                self.showStatus("Couldn’t undo: \(error.localizedDescription)", kind: .error)
            }
            self.undoTask = nil
            self.updateUndoTitles()
        }
    }

    private func updateUndoTitles() {
        undoTitle = undoStack.last?.title
        redoTitle = redoStack.last?.title
    }

    private func registerTransferUndo(isCut: Bool, pairs: [TransferPair]) {
        guard !pairs.isEmpty else { return }
        let title = isCut ? "Move" : "Copy"
        registerFileUndo(
            title: title,
            undo: {
                for pair in pairs.reversed() where FileManager.default.fileExists(atPath: pair.target.path) {
                    _ = try TrashService.recycle(pair.target)
                }
            },
            redo: {
                for pair in pairs {
                    if isCut {
                        try FileManager.default.moveItem(at: pair.source, to: pair.target)
                    } else {
                        try FileManager.default.copyItem(at: pair.source, to: pair.target)
                    }
                }
            }
        )
    }

    // MARK: Status

    func showStatus(_ text: String, kind: ExplorerStatus.Kind = .info) {
        let status = ExplorerStatus(text: text, kind: kind)
        self.status = status
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard let self, !Task.isCancelled, self.status?.id == status.id else { return }
            self.status = nil
        }
    }

    // MARK: Sidebar tree

    func isExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
            if treeChildren[path] == nil {
                Task { await loadTreeChildren(path: path) }
            }
        }
    }

    func loadTreeChildren(path: String, force: Bool = false) async {
        if !force, treeChildren[path] != nil { return }
        if treeLoading.contains(path) { return }
        treeLoading.insert(path)
        defer { treeLoading.remove(path) }

        let includeHidden = showHidden
        let url = URL(fileURLWithPath: path)
        let entries = await Task.detached(priority: .utility) {
            FileSystemService.subdirectories(at: url, includeHidden: includeHidden)
        }.value
        treeChildren[path] = entries
    }

    // MARK: Internal loading

    private func openDirectory(_ target: URL, pushHistory: Bool, selecting selectionPaths: Set<String>?) {
        var directory = target.standardizedFileURL
        var pending = selectionPaths ?? []

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
            showStatus("“\(directory.lastPathComponent)” can’t be found.", kind: .error)
            return
        }

        if !isDirectory.boolValue {
            pending.insert(directory.path)
            directory = directory.deletingLastPathComponent().standardizedFileURL
        }

        let changed = directory.path != currentURL.path
        if pushHistory {
            recordHistory(directory)
        }

        cancelRecursiveSearch()
        cancelFolderSizeCalculation(announce: false)
        storageSizeGeneration &+= 1
        storageSizeTask?.cancel()
        storageSizeWorker?.cancel()
        storageSizeTask = nil
        storageSizeWorker = nil
        isCalculatingStorageSize = false
        storageFolderSize = nil
        currentURL = directory
        volume = FileSystemService.volumeInfo(for: directory)
        currentFolderName = displayName(for: directory)
        isEditingPath = false
        pathError = false
        pathDraft = ""
        filterText = ""

        if changed {
            items = []
            displayedItems = []
            selection = []
        }
        pendingSelection = pending

        loadItems()
        ensureTreeReveal()
    }

    private func displayName(for directory: URL) -> String {
        if directory.path == "/" {
            return volume?.name ?? "Macintosh HD"
        }
        let name = FileManager.default.displayName(atPath: directory.path)
        return name.isEmpty ? directory.lastPathComponent : name
    }

    private func recordHistory(_ url: URL) {
        if history.indices.contains(historyIndex), history[historyIndex].path == url.path {
            return
        }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(url)
        if history.count > 200 {
            history.removeFirst(history.count - 200)
        }
        historyIndex = history.count - 1
        canGoBack = historyIndex > 0
        canGoForward = false
    }

    private func loadItems() {
        loadGeneration += 1
        let generation = loadGeneration
        let url = currentURL
        let includeHidden = showHidden
        let pending = pendingSelection
        pendingSelection = nil

        isLoading = true
        loadError = nil
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let result: ([FileItem], String?) = await Task.detached(priority: .userInitiated) {
                do {
                    return (try FileSystemService.listDirectory(at: url, includeHidden: includeHidden), nil)
                } catch {
                    return ([], error.localizedDescription)
                }
            }.value

            guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
            self.isLoading = false

            if let error = result.1 {
                self.items = []
                self.displayedItems = []
                self.loadError = "Can’t open “\(self.currentFolderName)”. \(error)"
                self.showStatus(self.loadError ?? "Can’t open folder.", kind: .error)
                return
            }

            self.items = result.0
            self.rebuildVisibleItems()
            let itemIDs = Set(self.items.map(\.id))
            if let pending {
                self.selection = pending.intersection(itemIDs)
            } else {
                self.selection = self.selection.intersection(itemIDs)
            }
        }
    }

    func reload(preserveSelection: Bool = true, selecting: Set<String>? = nil) {
        pendingSelection = selecting ?? (preserveSelection ? nil : [])
        loadItems()
    }

    private func rebuildVisibleItems() {
        let filtered: [FileItem]
        if isRecursiveSearchActive {
            filtered = searchResults
        } else if filterText.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
        }
        let sorted = FileSorter.sorted(filtered, by: sortField, ascending: sortAscending)
        displayedItems = sorted
        let visibleIDs = Set(sorted.map(\.id))
        if !selection.isSubset(of: visibleIDs) {
            selection = selection.intersection(visibleIDs)
        }
    }

    private func ensureTreeReveal() {
        revealTask?.cancel()
        let target = currentURL
        revealTask = Task { [weak self] in
            guard let self else { return }
            guard let root = self.treeRoots.first(where: { PathTools.isDescendant(target, of: $0.url) }) else { return }

            var chain: [URL] = []
            var cursor = target
            while true {
                chain.append(cursor)
                if cursor.path == root.url.path { break }
                let parent = cursor.deletingLastPathComponent()
                if parent.path == cursor.path || !PathTools.isDescendant(parent, of: root.url) { break }
                cursor = parent
            }
            chain.reverse()

            for directory in chain.dropLast() {
                if Task.isCancelled { return }
                self.expandedPaths.insert(directory.path)
                if self.treeChildren[directory.path] == nil {
                    await self.loadTreeChildren(path: directory.path)
                }
            }

            guard !Task.isCancelled else { return }
            self.treeRevealRequest = TreeRevealRequest(path: target.path)
        }
    }

    private func invalidateTree(_ directory: URL) {
        let path = directory.path
        treeChildren.removeValue(forKey: path)
        if expandedPaths.contains(path) {
            Task { await loadTreeChildren(path: path, force: true) }
        }
    }

    private func forgetTreeSubtree(_ path: String) {
        let prefix = path + "/"
        expandedPaths = expandedPaths.filter { $0 != path && !$0.hasPrefix(prefix) }
        treeChildren = treeChildren.filter { $0.key != path && !$0.key.hasPrefix(prefix) }
    }
}
