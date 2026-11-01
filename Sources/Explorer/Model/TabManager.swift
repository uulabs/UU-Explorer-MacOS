import Combine
import Foundation

struct ExplorerTabState: Codable, Equatable {
    var path: String
    var history: [String]
    var historyIndex: Int
    var sortField: String
    var sortAscending: Bool
    var showHidden: Bool
    var filterText: String
    var viewMode: String
    var selection: [String]
}

struct ExplorerTab: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var state: ExplorerTabState
}

private struct TabSession: Codable {
    var tabs: [ExplorerTab]
    var activeID: UUID?
}

@MainActor
final class TabManager: ObservableObject {
    @Published private(set) var tabs: [ExplorerTab]
    @Published private(set) var activeTabID: UUID

    var onCloseWindow: (() -> Void)?

    private let model: ExplorerModel
    private let defaults: UserDefaults
    private let sessionKey = "UUExplorer.tabs.v1"
    private let restoresSavedSession: Bool
    private let persistsSession: Bool
    private var closedTabs: [ExplorerTab] = []
    private var isRestoring = false
    private var waitsForSavedRestore = false
    private var cancellables = Set<AnyCancellable>()

    init(model: ExplorerModel, restoreSession: Bool) {
        self.model = model
        self.defaults = .standard
        self.restoresSavedSession = restoreSession
        self.persistsSession = restoreSession

        if restoreSession, let saved = Self.loadSession(from: defaults, key: sessionKey) {
            let validTabs = saved.tabs.filter { tab in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: tab.state.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            if !validTabs.isEmpty {
                self.tabs = validTabs
                self.activeTabID = validTabs.first(where: { $0.id == saved.activeID })?.id
                    ?? validTabs[0].id
                self.waitsForSavedRestore = true
            } else {
                let initial = Self.tab(from: model)
                self.tabs = [initial]
                self.activeTabID = initial.id
            }
        } else {
            let initial = Self.tab(from: model)
            self.tabs = [initial]
            self.activeTabID = initial.id
        }

        model.$currentURL
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.isRestoring, !self.waitsForSavedRestore else { return }
                self.captureActive()
                self.save()
            }
            .store(in: &cancellables)
    }

    var activeIndex: Int? {
        tabs.firstIndex { $0.id == activeTabID }
    }

    var canGoToNextTab: Bool { tabs.count > 1 }
    var canGoToPreviousTab: Bool { tabs.count > 1 }
    var canReopenClosedTab: Bool { !closedTabs.isEmpty }
    var canDetachActiveTab: Bool { tabs.count > 1 }

    func restoreOnLaunchIfNeeded() {
        if waitsForSavedRestore, let index = activeIndex {
            waitsForSavedRestore = false
            isRestoring = true
            model.restoreTabState(tabs[index].state)
            isRestoring = false
        } else {
            waitsForSavedRestore = false
            captureActive()
            save()
        }
    }

    func newTab(at url: URL? = nil) {
        captureActive()
        let target = (url ?? model.currentURL).standardizedFileURL
        let state = ExplorerTabState(
            path: target.path,
            history: [target.path],
            historyIndex: 0,
            sortField: model.sortField.rawValue,
            sortAscending: model.sortAscending,
            showHidden: model.showHidden,
            filterText: "",
            viewMode: model.viewMode.rawValue,
            selection: []
        )
        let tab = ExplorerTab(id: UUID(), title: displayName(for: target), state: state)
        var updated = tabs
        let insertion = min((activeIndex ?? tabs.count - 1) + 1, tabs.count)
        updated.insert(tab, at: insertion)
        tabs = updated
        activeTabID = tab.id
        isRestoring = true
        model.restoreTabState(state)
        isRestoring = false
        save()
    }

    func selectTab(_ id: UUID) {
        guard id != activeTabID, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        captureActive()
        activeTabID = id
        isRestoring = true
        model.restoreTabState(tabs[index].state)
        isRestoring = false
        save()
    }

    func selectNextTab() {
        guard tabs.count > 1, let index = activeIndex else { return }
        selectTab(tabs[(index + 1) % tabs.count].id)
    }

    func selectPreviousTab() {
        guard tabs.count > 1, let index = activeIndex else { return }
        selectTab(tabs[(index - 1 + tabs.count) % tabs.count].id)
    }

    func closeActiveTab() {
        closeTab(activeTabID)
    }

    func closeTab(_ id: UUID) {
        captureActive()
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closed = tabs.remove(at: index)
        closedTabs.append(closed)
        if tabs.isEmpty {
            save()
            onCloseWindow?()
            return
        }
        if id == activeTabID {
            let next = tabs[min(index, tabs.count - 1)]
            activeTabID = next.id
            isRestoring = true
            model.restoreTabState(next.state)
            isRestoring = false
        }
        save()
    }

    func takeActiveTabForDetachedWindow() -> ExplorerTab? {
        captureActive()
        guard tabs.count > 1, let index = activeIndex else { return nil }
        var updated = tabs
        let detached = updated.remove(at: index)
        tabs = updated
        let next = updated[min(index, updated.count - 1)]
        activeTabID = next.id
        isRestoring = true
        model.restoreTabState(next.state)
        isRestoring = false
        save()
        return detached
    }

    func adoptDetachedState(_ state: ExplorerTabState) {
        guard let index = activeIndex else { return }
        var updated = tabs
        updated[index].state = state
        updated[index].title = (state.path as NSString).lastPathComponent
        tabs = updated
        isRestoring = true
        model.restoreTabState(state)
        isRestoring = false
        save()
    }

    func reopenClosedTab() {
        guard let closed = closedTabs.popLast() else { return }
        captureActive()
        var updated = tabs
        let insertion = min((activeIndex ?? tabs.count - 1) + 1, tabs.count)
        updated.insert(closed, at: insertion)
        tabs = updated
        activeTabID = closed.id
        isRestoring = true
        model.restoreTabState(closed.state)
        isRestoring = false
        save()
    }

    func moveTab(_ sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = tabs.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        captureActive()
        var updated = tabs
        let moved = updated.remove(at: sourceIndex)
        let insertion = min(targetIndex, updated.count)
        updated.insert(moved, at: insertion)
        tabs = updated
        save()
    }

    func captureActiveAndSave() {
        captureActive()
        save()
    }

    private func captureActive() {
        guard let index = activeIndex else { return }
        var updated = tabs
        updated[index].state = model.captureTabState()
        updated[index].title = model.currentFolderName
        tabs = updated
    }

    private func save() {
        guard persistsSession else { return }
        let session = TabSession(tabs: tabs, activeID: activeTabID)
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: sessionKey)
    }

    private static func loadSession(from defaults: UserDefaults, key: String) -> TabSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TabSession.self, from: data)
    }

    private static func tab(from model: ExplorerModel) -> ExplorerTab {
        ExplorerTab(
            id: UUID(),
            title: model.currentFolderName,
            state: model.captureTabState()
        )
    }

    private func displayName(for url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }
}
