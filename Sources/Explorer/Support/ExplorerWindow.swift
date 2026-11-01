import AppKit

/// Handles side buttons wherever the pointer is in the browser window.
final class ExplorerWindow: NSWindow {
    var onBecomeKey: (() -> Void)?
    var navigateBack: (() -> Void)?
    var navigateForward: (() -> Void)?
    var copyFiles: (() -> Void)?
    var cutFiles: (() -> Void)?
    var pasteFiles: (() -> Void)?
    var canCopyFiles: (() -> Bool)?
    var canPasteFiles: (() -> Bool)?
    var undoFiles: (() -> Void)?
    var redoFiles: (() -> Void)?
    var canUndoFiles: (() -> Bool)?
    var canRedoFiles: (() -> Bool)?
    var undoTitle: (() -> String?)?
    var redoTitle: (() -> String?)?

    @objc func copy(_ sender: Any?) {
        guard canCopyFiles?() ?? false else { return }
        copyFiles?()
    }

    @objc func cut(_ sender: Any?) {
        guard canCopyFiles?() ?? false else { return }
        cutFiles?()
    }

    @objc func paste(_ sender: Any?) {
        guard canPasteFiles?() ?? false else { return }
        pasteFiles?()
    }

    @objc func undo(_ sender: Any?) {
        guard canUndoFiles?() ?? false else { return }
        undoFiles?()
    }

    @objc func redo(_ sender: Any?) {
        guard canRedoFiles?() ?? false else { return }
        redoFiles?()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return canCopyFiles?() ?? false
        case #selector(paste(_:)):
            return canPasteFiles?() ?? false
        case #selector(undo(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = (undoTitle?()?.isEmpty == false) ? "Undo \(undoTitle?() ?? "")" : "Undo"
            }
            return canUndoFiles?() ?? false
        case #selector(redo(_:)):
            if let menuItem = item as? NSMenuItem {
                menuItem.title = (redoTitle?()?.isEmpty == false) ? "Redo \(redoTitle?() ?? "")" : "Redo"
            }
            return canRedoFiles?() ?? false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKey?()
    }

    override func sendEvent(_ event: NSEvent) {
        if attachedSheet == nil,
           event.type == .otherMouseDown || event.type == .otherMouseUp,
           event.buttonNumber == 3 || event.buttonNumber == 4 {
            // Consume the press as well, but navigate only once, on release.
            if event.type == .otherMouseUp {
                if event.buttonNumber == 3 { navigateBack?() }
                else { navigateForward?() }
            }
            return
        }
        super.sendEvent(event)
    }
}
