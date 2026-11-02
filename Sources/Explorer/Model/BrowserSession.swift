import AppKit
import SwiftUI

enum BrowserPaneSide {
    case primary
    case secondary
}

@MainActor
final class BrowserPane {
    let model: ExplorerModel
    let tabs: TabManager

    init(startURL: URL?, restoreSession: Bool, hideSidebar: Bool = false) {
        let model = ExplorerModel(startURL: startURL)
        let tabs = TabManager(model: model, restoreSession: restoreSession)
        model.openInNewTabHandler = { [weak tabs] url in
            tabs?.newTab(at: url)
        }
        if hideSidebar, model.isSidebarVisible {
            model.setSidebarVisible(false, persist: false)
        }
        model.start()
        self.model = model
        self.tabs = tabs
    }
}

@MainActor
final class BrowserSession: ObservableObject {
    let primary: BrowserPane
    @Published private(set) var secondary: BrowserPane?
    @Published private(set) var isSplitView = false
    @Published private(set) var activeSide: BrowserPaneSide = .primary
    @Published var isShowingFolderCompare = false
    weak var window: ExplorerWindow?

    var onActivePaneChange: (() -> Void)?

    init(primary: BrowserPane) {
        self.primary = primary
        configurePaneHandlers()
    }

    private func configurePaneHandlers() {
        primary.model.transferToOtherPaneHandler = { [weak self] copy in
            guard let self else { return }
            self.transferFromPane(self.primary.model, copy: copy)
        }
        secondary?.model.transferToOtherPaneHandler = { [weak self, weak secondary] copy in
            guard let secondary else { return }
            self?.transferFromPane(secondary.model, copy: copy)
        }
    }

    private func transferFromPane(_ source: ExplorerModel, copy: Bool) {
        guard isSplitView, let secondary else { return }
        let destination = source === primary.model ? secondary.model : primary.model
        let urls = source.selectedItems.map(\.url)
        guard !urls.isEmpty else {
            source.showStatus("Select items before transferring to the other pane.", kind: .error)
            return
        }
        source.transfer(urls, to: destination.currentURL, copy: copy) { [weak destination] in
            destination?.reload()
        }
    }

    func copyActiveSelectionToOtherPane() {
        transferFromPane(activePane.model, copy: true)
    }

    func moveActiveSelectionToOtherPane() {
        transferFromPane(activePane.model, copy: false)
    }

    var canTransferToOtherPane: Bool {
        isSplitView && secondary != nil
    }

    func beginFolderCompare() {
        guard isSplitView, secondary != nil else {
            primary.model.showStatus("Open Split View to compare folders.", kind: .error)
            return
        }
        isShowingFolderCompare = true
    }

    var activePane: BrowserPane {
        if isSplitView, activeSide == .secondary, let secondary {
            return secondary
        }
        return primary
    }

    func toggleSplitView() {
        if isSplitView {
            isSplitView = false
            activeSide = .primary
            window?.minSize = NSSize(width: 960, height: 560)
        } else {
            if secondary == nil {
                secondary = BrowserPane(
                    startURL: activePane.model.currentURL,
                    restoreSession: false,
                    hideSidebar: true
                )
            }
            configurePaneHandlers()
            isSplitView = true
            activeSide = .primary
            window?.minSize = NSSize(width: 1_200, height: 560)
        }
        onActivePaneChange?()
    }

    func activate(_ side: BrowserPaneSide) {
        guard isSplitView, side != activeSide else { return }
        if side == .secondary, secondary == nil { return }
        activeSide = side
        onActivePaneChange?()
    }
}
