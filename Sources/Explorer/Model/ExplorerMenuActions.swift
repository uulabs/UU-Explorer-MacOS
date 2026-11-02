import AppKit
import ExplorerCore

@MainActor
final class ExplorerMenuActions: NSObject, NSMenuItemValidation {
    weak var model: ExplorerModel?
    weak var tabs: TabManager?
    var newWindow: (() -> Void)?
    var moveTabToNewWindow: (() -> Void)?
    var splitViewToggle: (() -> Void)?
    var splitViewIsActive: (() -> Bool)?
    var compareFolders: (() -> Void)?
    var compareFoldersAvailable: (() -> Bool)?
    var copyToOtherPane: (() -> Void)?
    var moveToOtherPane: (() -> Void)?
    var canTransferToOtherPane: (() -> Bool)?

    init(model: ExplorerModel, tabs: TabManager? = nil) {
        self.model = model
        self.tabs = tabs
    }

    func update(model: ExplorerModel, tabs: TabManager) {
        self.model = model
        self.tabs = tabs
    }

    // MARK: File

    @objc func newFolder(_ sender: Any?) { model?.beginNewFolder() }
    @objc func newFile(_ sender: Any?) { model?.beginNewFile() }
    @objc func open(_ sender: Any?) { model?.openSelectedItems() }
    @objc func rename(_ sender: Any?) { model?.beginRenameSelected() }
    @objc func batchRename(_ sender: Any?) { model?.beginBatchRename() }
    @objc func moveToTrash(_ sender: Any?) { model?.moveSelectionToTrash() }
    @objc func copyPath(_ sender: Any?) { model?.copySelectionPath() }
    @objc func revealInFinder(_ sender: Any?) { model?.revealSelectionInFinder() }
    @objc func quickLook(_ sender: Any?) { model?.quickLookSelection() }
    @objc func largerThumbnails(_ sender: Any?) { model?.increaseGalleryThumbnailSize() }
    @objc func smallerThumbnails(_ sender: Any?) { model?.decreaseGalleryThumbnailSize() }
    @objc func toggleCurrentFavorite(_ sender: Any?) { model?.toggleCurrentFolderFavorite() }
    @objc func openCurrentInTerminal(_ sender: Any?) { model?.openCurrentFolderInTerminal() }
    @objc func addNetworkLocation(_ sender: Any?) { model?.addNetworkLocation() }
    @objc func saveSearch(_ sender: Any?) { model?.saveCurrentSearch() }
    @objc func togglePreviewPane(_ sender: Any?) { model?.togglePreviewPane() }
    @objc func properties(_ sender: Any?) { model?.showProperties() }
    @objc func closeWindow(_ sender: Any?) { NSApp.keyWindow?.performClose(nil) }
    @objc func newWindow(_ sender: Any?) { newWindow?() }
    @objc func moveTabToNewWindow(_ sender: Any?) { moveTabToNewWindow?() }
    @objc func toggleSplitView(_ sender: Any?) { splitViewToggle?() }
    @objc func compareFoldersAction(_ sender: Any?) { compareFolders?() }
    @objc func copyToOtherPaneAction(_ sender: Any?) { copyToOtherPane?() }
    @objc func moveToOtherPaneAction(_ sender: Any?) { moveToOtherPane?() }
    @objc func newTab(_ sender: Any?) { tabs?.newTab() }
    @objc func closeTab(_ sender: Any?) { tabs?.closeActiveTab() }
    @objc func nextTab(_ sender: Any?) { tabs?.selectNextTab() }
    @objc func previousTab(_ sender: Any?) { tabs?.selectPreviousTab() }
    @objc func reopenClosedTab(_ sender: Any?) { tabs?.reopenClosedTab() }

    // MARK: View

    @objc func refresh(_ sender: Any?) { model?.refresh() }
    @objc func toggleHiddenFiles(_ sender: Any?) { model?.toggleHiddenFiles() }
    @objc func toggleSidebar(_ sender: Any?) { model?.toggleSidebar() }
    @objc func showDetails(_ sender: Any?) { model?.setViewMode(.details) }
    @objc func showGallery(_ sender: Any?) { model?.setViewMode(.gallery) }

    @objc func sortByName(_ sender: Any?) {
        model?.setSort(field: .name, ascending: true)
    }

    @objc func sortByDate(_ sender: Any?) {
        model?.setSort(field: .dateModified, ascending: false)
    }

    @objc func sortByType(_ sender: Any?) {
        model?.setSort(field: .kind, ascending: true)
    }

    @objc func sortBySize(_ sender: Any?) {
        model?.setSort(field: .size, ascending: false)
    }

    // MARK: Go

    @objc func goBack(_ sender: Any?) { model?.goBack() }
    @objc func goForward(_ sender: Any?) { model?.goForward() }
    @objc func goUp(_ sender: Any?) { model?.goUp() }
    @objc func goToFolder(_ sender: Any?) { model?.beginPathEditing() }
    @objc func goHome(_ sender: Any?) { model?.goHome() }

    @objc func goDesktop(_ sender: Any?) {
        guard let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return }
        model?.go(to: url)
    }

    @objc func goDocuments(_ sender: Any?) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        model?.go(to: url)
    }

    @objc func goDownloads(_ sender: Any?) {
        guard let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        model?.go(to: url)
    }

    @objc func goApplications(_ sender: Any?) {
        model?.go(to: URL(fileURLWithPath: "/Applications"))
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let model else { return false }
        let hasSelection = !model.selection.isEmpty
        let canAct = model.nameEditor == nil && !isEditingText

        switch menuItem.action {
        case #selector(newWindow(_:)):
            return canAct
        case #selector(moveTabToNewWindow(_:)):
            return canAct && (tabs?.canDetachActiveTab ?? false)
        case #selector(toggleSplitView(_:)):
            menuItem.state = (splitViewIsActive?() ?? false) ? .on : .off
            return canAct
        case #selector(compareFoldersAction(_:)):
            return canAct && (compareFoldersAvailable?() ?? false)
        case #selector(copyToOtherPaneAction(_:)), #selector(moveToOtherPaneAction(_:)):
            return canAct && (canTransferToOtherPane?() ?? false) && hasSelection
        case #selector(newTab(_:)), #selector(closeTab(_:)):
            return canAct
        case #selector(nextTab(_:)), #selector(previousTab(_:)):
            return canAct && (tabs?.canGoToNextTab ?? false)
        case #selector(reopenClosedTab(_:)):
            return canAct && (tabs?.canReopenClosedTab ?? false)
        case #selector(newFolder(_:)), #selector(newFile(_:)):
            return canAct
        case #selector(open(_:)), #selector(copyPath(_:)), #selector(revealInFinder(_:)), #selector(moveToTrash(_:)), #selector(quickLook(_:)):
            return canAct && hasSelection
        case #selector(largerThumbnails(_:)), #selector(smallerThumbnails(_:)):
            return model.viewMode == .gallery
        case #selector(toggleCurrentFavorite(_:)):
            menuItem.title = model.currentFolderIsFavorite
                ? "Remove Current Folder from Favourites"
                : "Pin Current Folder to Favourites"
            return canAct
        case #selector(togglePreviewPane(_:)):
            menuItem.title = model.isPreviewPaneVisible ? "Hide Preview Pane" : "Show Preview Pane"
            menuItem.state = model.isPreviewPaneVisible ? .on : .off
            return canAct
        case #selector(rename(_:)), #selector(properties(_:)):
            return canAct && model.selection.count == 1
        case #selector(batchRename(_:)):
            return canAct && !model.selection.isEmpty
        case #selector(goBack(_:)):
            return canAct && model.canGoBack
        case #selector(goForward(_:)):
            return canAct && model.canGoForward
        case #selector(goUp(_:)):
            return canAct && model.currentURL.path != "/"
        case #selector(goHome(_:)), #selector(goDesktop(_:)), #selector(goDocuments(_:)),
             #selector(goDownloads(_:)), #selector(goApplications(_:)):
            return canAct
        case #selector(goToFolder(_:)):
            return model.nameEditor == nil
        case #selector(toggleHiddenFiles(_:)):
            menuItem.state = model.showHidden ? .on : .off
            return model.nameEditor == nil
        case #selector(toggleSidebar(_:)):
            menuItem.state = model.isSidebarVisible ? .on : .off
            return true
        case #selector(showDetails(_:)):
            menuItem.state = model.viewMode == .details ? .on : .off
            return true
        case #selector(showGallery(_:)):
            menuItem.state = model.viewMode == .gallery ? .on : .off
            return true
        case #selector(sortByName(_:)):
            menuItem.state = model.sortField == .name ? .on : .off
            return true
        case #selector(sortByDate(_:)):
            menuItem.state = model.sortField == .dateModified ? .on : .off
            return true
        case #selector(sortByType(_:)):
            menuItem.state = model.sortField == .kind ? .on : .off
            return true
        case #selector(sortBySize(_:)):
            menuItem.state = model.sortField == .size ? .on : .off
            return true
        case #selector(refresh(_:)):
            return model.nameEditor == nil
        case #selector(closeWindow(_:)):
            return true
        default:
            return true
        }
    }

    private var isEditingText: Bool {
        guard let window = NSApp.keyWindow else { return false }
        return window.firstResponder is NSTextView
    }
}
