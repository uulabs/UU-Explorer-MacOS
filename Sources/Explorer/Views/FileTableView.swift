import AppKit
import ExplorerCore
import SwiftUI

final class ExplorerScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

final class ThemedHeaderView: NSTableHeaderView {
    var theme: ResolvedTheme?

    override func draw(_ dirtyRect: NSRect) {
        guard let tableView else { return }
        let theme = themeOverride
        theme.contentFieldNS.setFill()
        dirtyRect.fill()

        let sortedDescriptor = tableView.sortDescriptors.first
        let columns = tableView.tableColumns
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)

        for (index, column) in columns.enumerated() {
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }

            let sorted = sortedDescriptor?.key == column.identifier.rawValue
            let arrowSpace: CGFloat = sorted ? 18 : 0
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = column.headerCell.alignment
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: theme.contentTextNS,
                .paragraphStyle: paragraph
            ]

            let textHeight = ceil((column.title as NSString).size(withAttributes: [.font: font]).height)
            var textRect = rect.insetBy(dx: 8, dy: 0)
            textRect.size.width -= arrowSpace
            textRect.origin.y = rect.midY - textHeight / 2
            textRect.size.height = textHeight + 1
            (column.title as NSString).draw(in: textRect, withAttributes: attributes)

            if sorted {
                let ascending = sortedDescriptor?.ascending ?? true
                let size: CGFloat = 7
                let arrowRect = NSRect(
                    x: rect.maxX - 8 - size,
                    y: rect.midY - 3,
                    width: size,
                    height: 6
                )
                let path = NSBezierPath()
                let bottom = isFlipped ? arrowRect.maxY : arrowRect.minY
                let top = isFlipped ? arrowRect.minY : arrowRect.maxY
                let middleX = arrowRect.midX
                if ascending {
                    path.move(to: NSPoint(x: arrowRect.minX, y: bottom))
                    path.line(to: NSPoint(x: arrowRect.maxX, y: bottom))
                    path.line(to: NSPoint(x: middleX, y: top))
                } else {
                    path.move(to: NSPoint(x: arrowRect.minX, y: top))
                    path.line(to: NSPoint(x: arrowRect.maxX, y: top))
                    path.line(to: NSPoint(x: middleX, y: bottom))
                }
                path.close()
                theme.accentNS.setFill()
                path.fill()
            }

            if index < columns.count - 1 {
                theme.dividerNS.setFill()
                NSRect(x: rect.maxX - 0.5, y: rect.minY + 5, width: 1, height: max(0, rect.height - 10)).fill()
            }
        }

        theme.dividerNS.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    private var themeOverride: ResolvedTheme {
        if let theme { return theme }
        return ResolvedTheme(settings: .default, mode: .light)
    }
}

final class ExplorerTableView: NSTableView {
    private var didRequestInitialFocus = false
    var keyHandler: ((NSEvent) -> Bool)?
    var contextMenuProvider: ((Int) -> NSMenu?)?
    var copyHandler: (() -> Void)?
    var cutHandler: (() -> Void)?
    var pasteHandler: (() -> Void)?
    var canPasteHandler: (() -> Bool)?
    var newTabHandler: ((Int) -> Bool)?
    var firstResponderHandler: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, !didRequestInitialFocus else { return }
        didRequestInitialFocus = true
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            firstResponderHandler?()
        }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        return contextMenuProvider?(row)
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            let row = self.row(at: convert(event.locationInWindow, from: nil))
            if row >= 0, newTabHandler?(row) == true {
                return
            }
        }
        super.otherMouseDown(with: event)
    }

    @objc func copy(_ sender: Any?) {
        copyHandler?()
    }

    @objc func cut(_ sender: Any?) {
        cutHandler?()
    }

    @objc func paste(_ sender: Any?) {
        pasteHandler?()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return !selectedRowIndexes.isEmpty
        case #selector(paste(_:)):
            return canPasteHandler?() ?? false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}

final class ExplorerRowView: NSTableRowView {
    var accentColor: NSColor = .controlAccentColor

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        accentColor.withAlphaComponent(0.24).setFill()
        NSBezierPath(rect: bounds).fill()
        accentColor.withAlphaComponent(0.9).setFill()
        NSRect(x: bounds.minX, y: bounds.minY, width: 3, height: bounds.height).fill()
    }
}

private final class ExplorerNameCellView: NSTableCellView {
    let iconView = NSImageView()
    let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true

        addSubview(iconView)
        addSubview(label)
        imageView = iconView
        textField = label

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with item: FileItem, theme: ResolvedTheme) {
        iconView.image = AppIcons.icon(
            for: item,
            folderColor: theme.folderRGB,
            folderStyle: theme.folderIconStyle
        )
        label.stringValue = item.name
        label.textColor = item.isHidden ? .tertiaryLabelColor : .labelColor
        label.toolTip = item.name
        self.toolTip = item.url.path
        setAccessibilityLabel(item.name)
    }
}

private final class ExplorerTextCellView: NSTableCellView {
    let label = NSTextField(labelWithString: "")

    init(alignment: NSTextAlignment, color: NSColor, monospacedDigits: Bool = false) {
        super.init(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = monospacedDigits
            ? .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
            : .systemFont(ofSize: 12.5)
        label.alignment = alignment
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
        textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct FileTableView: NSViewRepresentable {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ExplorerScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let tableView = ExplorerTableView()
        tableView.style = .fullWidth
        tableView.rowHeight = 26
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.autoresizingMask = [.width]
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .textBackgroundColor
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 6, height: 1)
        let headerView = ThemedHeaderView()
        headerView.tableView = tableView
        tableView.headerView = headerView
        tableView.autosaveName = "Explorer.FileTable"
        tableView.autosaveTableColumns = true
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.registerForDraggedTypes([.fileURL])
        tableView.keyHandler = { [weak coordinator = context.coordinator] event in
            coordinator?.handleKeyDown(event) ?? false
        }
        tableView.contextMenuProvider = { [weak coordinator = context.coordinator] row in
            coordinator?.makeContextMenu(forRow: row)
        }
        tableView.copyHandler = { [weak coordinator = context.coordinator] in
            coordinator?.copySelection(cut: false)
        }
        tableView.cutHandler = { [weak coordinator = context.coordinator] in
            coordinator?.copySelection(cut: true)
        }
        tableView.pasteHandler = { [weak coordinator = context.coordinator] in
            coordinator?.model.pasteFiles()
        }
        tableView.canPasteHandler = { [weak coordinator = context.coordinator] in
            coordinator?.model.canPaste ?? false
        }
        tableView.newTabHandler = { [weak coordinator = context.coordinator] row in
            coordinator?.openInNewTab(row: row) ?? false
        }
        tableView.firstResponderHandler = { [weak coordinator = context.coordinator] in
            guard let model = coordinator?.model, model.isEditingPath else { return }
            model.cancelPathEditing()
        }

        context.coordinator.configureColumns(in: tableView)
        context.coordinator.tableView = tableView
        scrollView.documentView = tableView
        scrollView.onLayout = { [weak coordinator = context.coordinator] in
            coordinator?.fitColumns()
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            model: model,
            theme: themeStore.resolved(for: colorScheme)
        )
        context.coordinator.fitColumns()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: ExplorerModel
        weak var tableView: ExplorerTableView?
        private var items: [FileItem] = []
        private var lastSelection: Set<String> = []
        private var lastDirectoryPath: String?
        private var isSyncingSelection = false
        private var isSyncingSort = false
        private var isFittingColumns = false
        private var theme: ResolvedTheme?
        private var lastThemeSignature: String?
        private var lastFolderSizeSignature = ""
        private let fallbackTheme = ResolvedTheme(settings: .default, mode: .light)

        init(model: ExplorerModel) {
            self.model = model
        }

        func configureColumns(in tableView: NSTableView) {
            let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
            name.title = "Name"
            name.width = 360
            name.minWidth = 180
            name.maxWidth = 2000
            name.resizingMask = [.userResizingMask, .autoresizingMask]
            name.sortDescriptorPrototype = NSSortDescriptor(key: SortField.name.rawValue, ascending: true)

            let date = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dateModified"))
            date.title = "Date Modified"
            date.width = 165
            date.minWidth = 110
            date.resizingMask = [.userResizingMask]
            date.sortDescriptorPrototype = NSSortDescriptor(key: SortField.dateModified.rawValue, ascending: true)

            let kind = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
            kind.title = "Type"
            kind.width = 150
            kind.minWidth = 90
            kind.resizingMask = [.userResizingMask]
            kind.sortDescriptorPrototype = NSSortDescriptor(key: SortField.kind.rawValue, ascending: true)

            let size = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
            size.title = "Size"
            size.width = 100
            size.minWidth = 70
            size.resizingMask = [.userResizingMask]
            size.headerCell.alignment = .right
            size.sortDescriptorPrototype = NSSortDescriptor(key: SortField.size.rawValue, ascending: true)

            [name, date, kind, size].forEach(tableView.addTableColumn)
            tableView.sortDescriptors = [
                NSSortDescriptor(key: SortField.name.rawValue, ascending: true)
            ]
        }

        func update(model: ExplorerModel, theme: ResolvedTheme) {
            self.model = model
            self.theme = theme
            applyThemeIfNeeded(theme)
            let newItems = model.displayedItems
            let newIDs = newItems.map(\.id)
            let oldIDs = items.map(\.id)

            let sizeSignature = folderSizeSignature(for: model)
            if newIDs != oldIDs {
                let directoryChanged = lastDirectoryPath != model.currentURL.path
                items = newItems
                lastDirectoryPath = model.currentURL.path
                lastFolderSizeSignature = sizeSignature
                tableView?.reloadData()
                syncSelection(from: model.selection)
                lastSelection = model.selection
                scrollSelectionIntoView()
                updateSortDescriptors()
                if directoryChanged, let tableView, !items.isEmpty {
                    tableView.scrollRowToVisible(0)
                }
                return
            }

            if sizeSignature != lastFolderSizeSignature {
                lastFolderSizeSignature = sizeSignature
                tableView?.reloadData()
            }

            if model.selection != lastSelection {
                syncSelection(from: model.selection)
                lastSelection = model.selection
                scrollSelectionIntoView()
            }
            updateSortDescriptors()
        }

        private func folderSizeSignature(for model: ExplorerModel) -> String {
            let sizes = model.folderSizes
                .map { "\($0.key)=\($0.value.bytes)" }
                .sorted()
                .joined(separator: "|")
            let calculating = model.calculatingFolderPaths.sorted().joined(separator: ",")
            return "\(sizes)#\(calculating)"
        }

        private func applyThemeIfNeeded(_ theme: ResolvedTheme) {
            guard let tableView, let scrollView = tableView.enclosingScrollView else { return }
            let signature = theme.signature
            guard signature != lastThemeSignature else { return }
            lastThemeSignature = signature

            let appearance = NSAppearance(named: theme.isContentDark ? .darkAqua : .aqua)
            tableView.appearance = appearance
            scrollView.appearance = appearance
            tableView.backgroundColor = theme.contentNS
            scrollView.backgroundColor = theme.contentNS
            if let header = tableView.headerView as? ThemedHeaderView {
                header.theme = theme
                header.needsDisplay = true
            }
            tableView.reloadData()
            syncSelection(from: model.selection)
            lastSelection = model.selection
        }

        private func scrollSelectionIntoView() {
            guard let tableView, let firstRow = tableView.selectedRowIndexes.first else { return }
            tableView.scrollRowToVisible(firstRow)
        }

        func fitColumns() {
            guard !isFittingColumns,
                  let tableView,
                  let scrollView = tableView.enclosingScrollView else { return }
            let available = scrollView.contentSize.width
            guard available > 200 else { return }
            let columns = tableView.tableColumns
            guard columns.count >= 4 else { return }
            let name = columns[0]
            let fixedWidth = columns[1].width + columns[2].width + columns[3].width
            let gaps = tableView.intercellSpacing.width * CGFloat(columns.count + 1)
            let target = max(name.minWidth, available - fixedWidth - gaps - 1)
            guard abs(name.width - target) > 0.5 else { return }
            isFittingColumns = true
            name.width = target
            isFittingColumns = false
        }

        private func syncSelection(from selection: Set<String>) {
            guard let tableView else { return }
            isSyncingSelection = true
            let indexes = IndexSet(items.indices.filter { selection.contains(items[$0].id) })
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
            isSyncingSelection = false
        }

        private func updateSortDescriptors() {
            guard let tableView else { return }
            let desiredKey = model.sortField.rawValue
            let desiredAscending = model.sortAscending
            if tableView.sortDescriptors.first?.key != desiredKey
                || tableView.sortDescriptors.first?.ascending != desiredAscending {
                isSyncingSort = true
                tableView.sortDescriptors = [NSSortDescriptor(key: desiredKey, ascending: desiredAscending)]
                isSyncingSort = false
            }
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int {
            items.count
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = ExplorerRowView()
            view.accentColor = theme?.accentNS ?? .controlAccentColor
            return view
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard items.indices.contains(row), let columnID = tableColumn?.identifier.rawValue else { return nil }
            let item = items[row]

            switch columnID {
            case "name":
                let identifier = NSUserInterfaceItemIdentifier("Explorer.NameCell")
                let rowTheme = theme ?? fallbackTheme
                if let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ExplorerNameCellView {
                    cell.configure(with: item, theme: rowTheme)
                    return cell
                }
                let cell = ExplorerNameCellView(frame: .zero)
                cell.identifier = identifier
                cell.configure(with: item, theme: rowTheme)
                return cell

            case "dateModified":
                let cell = textCell(
                    in: tableView,
                    identifier: "Explorer.DateCell",
                    alignment: .left,
                    color: .secondaryLabelColor
                )
                cell.label.stringValue = item.dateModified?.formatted(date: .numeric, time: .shortened) ?? "—"
                cell.label.toolTip = cell.label.stringValue
                return cell

            case "kind":
                let cell = textCell(
                    in: tableView,
                    identifier: "Explorer.KindCell",
                    alignment: .left,
                    color: .secondaryLabelColor
                )
                cell.label.stringValue = item.kind
                cell.label.toolTip = item.kind
                return cell

            case "size":
                let cell = textCell(
                    in: tableView,
                    identifier: "Explorer.SizeCell",
                    alignment: .right,
                    color: .labelColor,
                    monospacedDigits: true
                )
                if item.isDirectory {
                    if let folderSize = model.folderSizes[item.url.path] {
                        cell.label.stringValue = ByteFormat.string(folderSize.bytes)
                        cell.label.toolTip = "\(ByteFormat.exact(folderSize.bytes)) — \(folderSize.fileCount) files, \(folderSize.directoryCount) folders\nAllocated: \(ByteFormat.exact(folderSize.allocatedBytes))"
                    } else if model.calculatingFolderPaths.contains(item.url.path) {
                        cell.label.stringValue = "…"
                        cell.label.toolTip = "Calculating folder size"
                    } else {
                        cell.label.stringValue = ""
                        cell.label.toolTip = "Choose Calculate Folder Sizes to measure this folder."
                    }
                } else {
                    cell.label.stringValue = ByteFormat.string(item.byteSize)
                    cell.label.toolTip = item.byteSize.map(ByteFormat.exact) ?? ""
                }
                return cell

            default:
                return nil
            }
        }

        private func textCell(
            in tableView: NSTableView,
            identifier: String,
            alignment: NSTextAlignment,
            color: NSColor,
            monospacedDigits: Bool = false
        ) -> ExplorerTextCellView {
            let reuseIdentifier = NSUserInterfaceItemIdentifier(identifier)
            if let cell = tableView.makeView(withIdentifier: reuseIdentifier, owner: self) as? ExplorerTextCellView {
                return cell
            }
            let cell = ExplorerTextCellView(
                alignment: alignment,
                color: color,
                monospacedDigits: monospacedDigits
            )
            cell.identifier = reuseIdentifier
            return cell
        }

        // MARK: Delegate

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection, let tableView else { return }
            let selection = Set(tableView.selectedRowIndexes.compactMap { index in
                items.indices.contains(index) ? items[index].id : nil
            })
            lastSelection = selection
            model.selection = selection
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            tableView.headerView?.needsDisplay = true
            guard !isSyncingSort,
                  let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key,
                  let field = SortField(rawValue: key) else { return }
            model.setSort(field: field, ascending: descriptor.ascending)
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            guard !draggedURLs(info).isEmpty else { return [] }
            if items.indices.contains(row), items[row].isDirectory {
                tableView.setDropRow(row, dropOperation: .on)
            }
            let local = (info.draggingSource as? ExplorerTableView) === (tableView as? ExplorerTableView)
            let copies = !local || (NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
            return copies ? .copy : .move
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            let urls = draggedURLs(info)
            guard !urls.isEmpty else { return false }
            let destination = items.indices.contains(row) && items[row].isDirectory
                ? items[row].url
                : model.currentURL
            let local = (info.draggingSource as? ExplorerTableView) === (tableView as? ExplorerTableView)
            let copies = !local || (NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
            model.transfer(urls, to: destination, copy: copies)
            return true
        }

        private func draggedURLs(_ info: NSDraggingInfo) -> [URL] {
            (info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]) ?? []
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard items.indices.contains(row) else { return nil }
            return items[row].url as NSURL
        }

        // MARK: Actions

        @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView, tableView.clickedRow >= 0, items.indices.contains(tableView.clickedRow) else { return }
            model.open(items[tableView.clickedRow])
        }

        func handleKeyDown(_ event: NSEvent) -> Bool {
            switch event.keyCode {
            case 36, 76: // Return / keypad Enter
                model.openSelectedItems()
                return true
            case 120: // F2
                model.beginRenameSelected()
                return true
            case 51 where event.modifierFlags.contains(.command): // ⌘⌫
                model.moveSelectionToTrash()
                return true
            case 53: // Escape
                if model.isFiltering {
                    model.setFilter("")
                    return true
                }
                return false
            default:
                return false
            }
        }

        func copySelection(cut: Bool) {
            model.copySelectionToPasteboard(cut: cut)
        }

        func openInNewTab(row: Int) -> Bool {
            guard items.indices.contains(row), items[row].isDirectory else { return false }
            model.openInNewTab(items[row].url)
            return true
        }

        func makeContextMenu(forRow row: Int) -> NSMenu? {
            let menu = NSMenu()
            menu.autoenablesItems = false

            if row >= 0, items.indices.contains(row) {
                if let tableView, !tableView.selectedRowIndexes.contains(row) {
                    tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
                let selectedCount = tableView?.selectedRowIndexes.count ?? 0

                menu.addItem(menuItem("Open", action: #selector(menuOpen(_:))))
                let applications = model.openWithApplications(for: items[row].url)
                if !applications.isEmpty {
                    let openWith = NSMenu()
                    for application in applications {
                        let appItem = NSMenuItem(
                            title: application.name,
                            action: #selector(menuOpenWithApplication(_:)),
                            keyEquivalent: ""
                        )
                        appItem.target = self
                        appItem.representedObject = application.url
                        let icon = application.icon
                        icon.size = NSSize(width: 16, height: 16)
                        appItem.image = icon
                        openWith.addItem(appItem)
                    }
                    let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                    parent.submenu = openWith
                    menu.addItem(parent)
                }
                if items[row].isDirectory {
                    menu.addItem(menuItem(
                        "Open in New Tab",
                        action: #selector(menuOpenInNewTab(_:)),
                        representedObject: items[row].url
                    ))
                }
                menu.addItem(.separator())
                menu.addItem(menuItem("Cut", action: #selector(menuCut(_:))))
                menu.addItem(menuItem("Copy", action: #selector(menuCopy(_:))))
                if items[row].isDirectory {
                    menu.addItem(menuItem(
                        "Paste Into Folder",
                        action: #selector(menuPasteIntoFolder(_:)),
                        enabled: model.canPaste,
                        representedObject: items[row].url
                    ))
                    menu.addItem(menuItem(
                        "Open in Terminal",
                        action: #selector(menuOpenInTerminal(_:)),
                        representedObject: items[row].url
                    ))
                }
                menu.addItem(.separator())
                menu.addItem(menuItem("Quick Look", action: #selector(menuQuickLook(_:))))
                menu.addItem(menuItem("Show in Finder", action: #selector(menuReveal(_:))))
                menu.addItem(menuItem("Copy Path", action: #selector(menuCopyPath(_:))))
                let copyPath = NSMenu()
                for format in PathCopyFormat.allCases {
                    copyPath.addItem(menuItem(
                        format.title,
                        action: #selector(menuCopyPathFormat(_:)),
                        representedObject: format.rawValue
                    ))
                }
                let copyPathParent = NSMenuItem(title: "Copy Path As", action: nil, keyEquivalent: "")
                copyPathParent.submenu = copyPath
                menu.addItem(copyPathParent)
                if items[row].isDirectory {
                    menu.addItem(menuItem(
                        model.isFavorite(items[row].url) ? "Remove from Favourites" : "Pin to Favourites",
                        action: #selector(menuToggleFavorite(_:)),
                        representedObject: items[row].url
                    ))
                }
                menu.addItem(menuItem(
                    "Compress",
                    action: #selector(menuCompress(_:)),
                    enabled: selectedCount == 1
                ))
                menu.addItem(menuItem(
                    "Compress with Password…",
                    action: #selector(menuEncryptedCompress(_:)),
                    enabled: selectedCount == 1
                ))
                if ArchiveService.isArchive(items[row].url) {
                    menu.addItem(menuItem(
                        "Browse Archive…",
                        action: #selector(menuBrowseArchive(_:)),
                        enabled: selectedCount == 1
                    ))
                    menu.addItem(menuItem(
                        "Extract Here",
                        action: #selector(menuExtractHere(_:)),
                        enabled: selectedCount == 1
                    ))
                    menu.addItem(menuItem(
                        "Extract To…",
                        action: #selector(menuExtract(_:)),
                        enabled: selectedCount == 1
                    ))
                }
                menu.addItem(.separator())
                menu.addItem(menuItem("New Folder", action: #selector(menuNewFolder(_:))))
                menu.addItem(menuItem("New File", action: #selector(menuNewFile(_:))))
                menu.addItem(.separator())
                menu.addItem(menuItem(
                    "Rename…",
                    action: #selector(menuRename(_:)),
                    enabled: selectedCount == 1
                ))
                menu.addItem(menuItem(
                    "Batch Rename…",
                    action: #selector(menuBatchRename(_:)),
                    enabled: selectedCount > 0
                ))
                menu.addItem(menuItem("Move to Trash", action: #selector(menuTrash(_:))))
                let quick = NSMenu()
                quick.addItem(menuItem("Duplicate", action: #selector(menuDuplicate(_:))))
                quick.addItem(menuItem("Create Symbolic Link", action: #selector(menuCreateLink(_:))))
                quick.addItem(menuItem("Share…", action: #selector(menuShare(_:))))
                quick.addItem(.separator())
                quick.addItem(menuItem("Copy Path", action: #selector(menuCopyPath(_:))))
                quick.addItem(menuItem("Show in Finder", action: #selector(menuReveal(_:))))
                let quickParent = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
                quickParent.submenu = quick
                menu.addItem(quickParent)
                let customActions = NSMenu()
                for action in model.customActions where action.isEnabled {
                    let item = NSMenuItem(
                        title: action.name.isEmpty ? "Untitled Action" : action.name,
                        action: #selector(menuRunCustomAction(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = action.id.uuidString
                    customActions.addItem(item)
                }
                if !customActions.items.isEmpty {
                    customActions.addItem(.separator())
                }
                customActions.addItem(menuItem("Manage Custom Actions…", action: #selector(menuManageCustomActions(_:))))
                let customParent = NSMenuItem(title: "Custom Actions", action: nil, keyEquivalent: "")
                customParent.submenu = customActions
                menu.addItem(customParent)
                if model.selectedItems.contains(where: \.isDirectory) {
                    menu.addItem(menuItem(
                        "Calculate Folder Size",
                        action: #selector(menuCalculateFolderSize(_:))
                    ))
                }
                menu.addItem(.separator())
                menu.addItem(menuItem("Properties…", action: #selector(menuProperties(_:)), enabled: selectedCount == 1))
                menu.addItem(.separator())
                menu.addItem(menuItem("UU Explorer Settings…", action: #selector(menuSettings(_:))))
            } else {
                menu.addItem(menuItem("New Folder", action: #selector(menuNewFolder(_:))))
                menu.addItem(menuItem("New File", action: #selector(menuNewFile(_:))))
                menu.addItem(.separator())
                menu.addItem(menuItem("Paste", action: #selector(menuPaste(_:)), enabled: model.canPaste))
                menu.addItem(menuItem("Open in Terminal", action: #selector(menuOpenCurrentInTerminal(_:))))
                menu.addItem(.separator())
                menu.addItem(menuItem("Refresh", action: #selector(menuRefresh(_:))))
                menu.addItem(.separator())
                menu.addItem(menuItem("Properties…", action: #selector(menuCurrentFolderProperties(_:))))
                menu.addItem(.separator())
                menu.addItem(menuItem("UU Explorer Settings…", action: #selector(menuSettings(_:))))
            }
            return menu
        }

        private func menuItem(
            _ title: String,
            action: Selector,
            enabled: Bool = true,
            representedObject: Any? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            item.representedObject = representedObject
            return item
        }

        @objc private func menuProperties(_ sender: Any?) { model.showProperties() }
        @objc private func menuSettings(_ sender: Any?) {
            SettingsWindowController.shared.showSettings()
        }
        @objc private func menuCurrentFolderProperties(_ sender: Any?) {
            PropertiesWindowController.show(for: model.currentURL)
        }
        @objc private func menuOpen(_ sender: Any?) { model.openSelectedItems() }
        @objc private func menuOpenInNewTab(_ sender: Any?) {
            guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return }
            model.openInNewTab(url)
        }
        @objc private func menuReveal(_ sender: Any?) { model.revealSelectionInFinder() }
        @objc private func menuCopyPath(_ sender: Any?) { model.copySelectionPath() }
        @objc private func menuCopyPathFormat(_ sender: Any?) {
            guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
                  let format = PathCopyFormat(rawValue: raw) else { return }
            model.copySelectionPath(as: format)
        }
        @objc private func menuRunCustomAction(_ sender: Any?) {
            guard let raw = (sender as? NSMenuItem)?.representedObject as? String,
                  let id = UUID(uuidString: raw),
                  let action = model.customActions.first(where: { $0.id == id }) else { return }
            model.runCustomAction(action)
        }
        @objc private func menuManageCustomActions(_ sender: Any?) { model.beginCustomActionManager() }
        @objc private func menuCut(_ sender: Any?) { model.copySelectionToPasteboard(cut: true) }
        @objc private func menuCopy(_ sender: Any?) { model.copySelectionToPasteboard() }
        @objc private func menuQuickLook(_ sender: Any?) { model.quickLookSelection() }
        @objc private func menuCompress(_ sender: Any?) { model.compressSelection() }
        @objc private func menuExtract(_ sender: Any?) { model.extractSelection() }
        @objc private func menuExtractHere(_ sender: Any?) { model.extractSelectionHere() }
        @objc private func menuToggleFavorite(_ sender: Any?) {
            guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return }
            model.toggleFavorite(url)
        }
        @objc private func menuPasteIntoFolder(_ sender: Any?) {
            guard let destination = (sender as? NSMenuItem)?.representedObject as? URL else { return }
            model.pasteFiles(into: destination)
        }
        @objc private func menuOpenInTerminal(_ sender: Any?) {
            guard let url = (sender as? NSMenuItem)?.representedObject as? URL else { return }
            model.openInTerminal(url)
        }
        @objc private func menuOpenCurrentInTerminal(_ sender: Any?) {
            model.openCurrentFolderInTerminal()
        }
        @objc private func menuNewFolder(_ sender: Any?) { model.beginNewFolder() }
        @objc private func menuNewFile(_ sender: Any?) { model.beginNewFile() }
        @objc private func menuRename(_ sender: Any?) { model.beginRenameSelected() }
        @objc private func menuBatchRename(_ sender: Any?) { model.beginBatchRename() }
        @objc private func menuOpenWithApplication(_ sender: Any?) {
            guard let app = (sender as? NSMenuItem)?.representedObject as? URL else { return }
            model.openSelection(with: app)
        }
        @objc private func menuDuplicate(_ sender: Any?) { model.duplicateSelection() }
        @objc private func menuCreateLink(_ sender: Any?) { model.createLinkSelection() }
        @objc private func menuShare(_ sender: Any?) { model.shareSelection() }
        @objc private func menuCalculateFolderSize(_ sender: Any?) { model.calculateSelectedFolderSizes() }
        @objc private func menuTrash(_ sender: Any?) { model.moveSelectionToTrash() }
        @objc private func menuPaste(_ sender: Any?) { model.pasteFiles() }
        @objc private func menuRefresh(_ sender: Any?) { model.refresh() }
        @objc private func menuCalculateVisibleFolderSizes(_ sender: Any?) { model.calculateVisibleFolderSizes() }
        @objc private func menuEncryptedCompress(_ sender: Any?) { model.beginEncryptedCompression() }
        @objc private func menuBrowseArchive(_ sender: Any?) { model.beginArchiveBrowsing() }
    }
}
