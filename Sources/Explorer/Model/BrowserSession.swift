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
    weak var window: ExplorerWindow?

    var onActivePaneChange: (() -> Void)?

    init(primary: BrowserPane) {
        self.primary = primary
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
