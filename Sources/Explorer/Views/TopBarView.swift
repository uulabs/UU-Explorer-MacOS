import ExplorerCore
import SwiftUI

struct TopBarView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        HStack(spacing: 5) {
            // Clears the standard window traffic lights.
            Color.clear
                .frame(width: 74, height: 1)

            NavButton(
                symbol: "chevron.left",
                help: "Back (⌘[)",
                isEnabled: model.canGoBack
            ) { model.goBack() }

            NavButton(
                symbol: "chevron.right",
                help: "Forward (⌘])",
                isEnabled: model.canGoForward
            ) { model.goForward() }

            NavButton(
                symbol: "arrow.up",
                help: "Enclosing folder (⌘↑)",
                isEnabled: model.currentURL.path != "/"
            ) { model.goUp() }

            NavButton(
                symbol: "arrow.clockwise",
                help: "Refresh (⌘R)",
                isEnabled: true
            ) { model.refresh() }

            PathBarView(model: model)
                .frame(maxWidth: .infinity)

            PathFilterField(model: model)

            ViewModeControl(model: model)

            Rectangle()
                .fill(theme.toolbarDivider)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 1)

            NavButton(
                symbol: "folder.badge.plus",
                help: "New Folder (⇧⌘N)",
                isEnabled: true
            ) { model.beginNewFolder() }

            MoreMenu(model: model)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(theme.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.toolbarDivider)
                .frame(height: 1)
        }
    }
}

struct NavButton: View {
    let symbol: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? theme.toolbarText : theme.toolbarText.opacity(0.38))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering && isEnabled ? theme.toolbarText.opacity(0.07) : Color.clear)
        )
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ViewModeControl: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    model.setViewMode(mode)
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                        .foregroundStyle(
                            model.viewMode == mode ? theme.toolbarText : theme.toolbarText.opacity(0.55)
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(model.viewMode == mode ? theme.accent.opacity(0.24) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("\(mode.title) view")
                .accessibilityLabel("\(mode.title) view")
            }
        }
        .padding(2)
        .background(theme.field, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(theme.toolbarDivider, lineWidth: 1)
        )
    }
}

struct PathFilterField: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var showSearchOptions = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    private var searchPlaceholder: String {
        guard let filter = activeFilterSummary else {
            return model.searchScope == .recursive ? "Search subfolders" : "Filter"
        }
        return "Search · \(filter)"
    }

    private var activeFilterSummary: String? {
        var parts: [String] = []
        if let size = model.searchFilter.minimumSize {
            parts.append("≥ \(ByteFormat.string(size))")
        }
        if let kind = model.searchFilter.kind {
            parts.append(kind.title)
        }
        if let days = model.searchFilter.modifiedWithinDays {
            parts.append("last \(days)d")
        }
        if model.searchFilter.textMode != .name {
            parts.append("contents")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }


    var body: some View {
        HStack(spacing: 5) {
            Menu {
                Button {
                    model.setSearchScope(.folder)
                } label: {
                    Label("This Folder", systemImage: model.searchScope == .folder ? "checkmark" : "folder")
                }
                .disabled(model.searchFilter.textMode != .name)
                Button {
                    model.setSearchScope(.recursive)
                } label: {
                    Label("Include Subfolders", systemImage: model.searchScope == .recursive ? "checkmark" : "arrow.triangle.branch")
                }
            } label: {
                Image(systemName: model.searchScope.symbol)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(model.searchScope == .recursive ? theme.accent : theme.toolbarText.opacity(0.62))
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Search scope: \(model.searchScope.title)")

            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.toolbarText.opacity(0.62))

            TextField(searchPlaceholder, text: Binding(
                get: { model.filterText },
                set: { model.setFilter($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(theme.toolbarText)
            .focused($isFocused)
            .onExitCommand {
                model.clearSearch()
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    model.cancelPathEditing()
                }
            }

            Button {
                showSearchOptions.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(
                        model.searchFilter.isActive || model.searchFilter.textMode != .name
                            ? theme.accent
                            : theme.toolbarText.opacity(0.62)
                    )
            }
            .buttonStyle(.plain)
            .help("Search options")
            .popover(isPresented: $showSearchOptions, arrowEdge: .bottom) {
                SearchOptionsView(model: model)
                    .environmentObject(themeStore)
            }

            if model.hasSearchCriteria {
                Button {
                    model.saveCurrentSearch()
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.toolbarText.opacity(0.62))
                }
                .buttonStyle(.plain)
                .help("Save this search")

                Button {
                    model.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.toolbarText.opacity(0.55))
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 7)
        .frame(width: 248, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.field)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isFocused ? theme.accent.opacity(0.9) : theme.toolbarDivider,
                    lineWidth: 1
                )
        )
        .help(model.searchScope == .recursive ? "Search this folder and its subfolders" : "Filter the current folder")
    }
}

struct MoreMenu: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Menu {
            Button("New Folder") { model.beginNewFolder() }
            Button("New File") { model.beginNewFile() }
            Divider()
            Button(model.showHidden ? "Hide Hidden Files" : "Show Hidden Files") {
                model.toggleHiddenFiles()
            }
            Button("Refresh") { model.refresh() }
            Divider()
            Button("Details View") { model.setViewMode(.details) }
                .disabled(model.viewMode == .details)
            Button("Gallery View") { model.setViewMode(.gallery) }
                .disabled(model.viewMode == .gallery)
            Divider()
            Menu("Sort By") {
                sortButton("Name", field: .name)
                sortButton("Date Modified", field: .dateModified)
                sortButton("Date Created", field: .dateCreated)
                sortButton("Type", field: .kind)
                sortButton("Size", field: .size)
                sortButton("Size on Disk", field: .sizeOnDisk)
                sortButton("Permissions", field: .permissions)
                sortButton("Owner", field: .owner)
                Divider()
                Button(model.sortAscending ? "Descending" : "Ascending") {
                    model.setSort(field: model.sortField, ascending: !model.sortAscending)
                }
            }
            Menu("Columns") {
                ForEach(ExplorerColumn.allCases) { column in
                    Button {
                        model.toggleColumn(column)
                    } label: {
                        Label(column.title, systemImage: model.visibleColumns.contains(column) ? "checkmark" : "square")
                    }
                }
            }
            Divider()
            Button("Quick Look") { model.quickLookSelection() }
                .disabled(model.selection.isEmpty)
            Button("Copy Path") { model.copySelectionPath() }
                .disabled(model.selection.isEmpty)
            Menu("Copy Path As") {
                ForEach(PathCopyFormat.allCases) { format in
                    Button(format.title) { model.copySelectionPath(as: format) }
                        .disabled(model.selection.isEmpty)
                }
            }
            Menu("Custom Actions") {
                ForEach(model.customActions.filter(\.isEnabled)) { action in
                    Button(action.name.isEmpty ? "Untitled Action" : action.name) {
                        model.runCustomAction(action)
                    }
                }
                if !model.customActions.isEmpty { Divider() }
                Button("Manage Custom Actions…") { model.beginCustomActionManager() }
            }
            Button("Show in Finder") { model.revealSelectionInFinder() }
                .disabled(model.selection.isEmpty)
            Button("Open in Terminal") { model.openCurrentFolderInTerminal() }
            Button("Add Network Share…") { model.addNetworkLocation() }
            Button("Android Devices…") { model.showAndroidBrowser() }
            Button(LoginItemController.isEnabled ? "Disable Launch at Login" : "Launch at Login") {
                do {
                    try LoginItemController.setEnabled(!LoginItemController.isEnabled)
                } catch {
                    model.showStatus("Couldn’t update Launch at Login: \(error.localizedDescription)", kind: .error)
                }
            }
            if model.selection.count == 1 {
                Button("Compress with Password…") { model.beginEncryptedCompression() }
                if let item = model.selectedItems.first, ArchiveService.isArchive(item.url) {
                    Button("Browse Archive…") { model.beginArchiveBrowsing() }
                }
            }
            if let first = model.selectedItems.first {
                let applications = model.openWithApplications(for: first.url)
                if !applications.isEmpty {
                    Menu("Open With") {
                        ForEach(applications) { application in
                            Button {
                                model.openSelection(with: application.url)
                            } label: {
                                Label {
                                    Text(application.name)
                                } icon: {
                                    Image(nsImage: application.icon)
                                }
                            }
                        }
                    }
                }
                Menu("Quick Actions") {
                    Button("Duplicate") { model.duplicateSelection() }
                    Button("Create Symbolic Link") { model.createLinkSelection() }
                    Button("Share…") { model.shareSelection() }
                }
            }
            Button("Find Large Files (100 MB+)") { model.findLargeFiles() }
            if model.hasSearchCriteria {
                Button("Save Search") { model.saveCurrentSearch() }
            }
            Button(model.currentFolderIsFavorite ? "Remove Current Folder from Favourites" : "Pin Current Folder to Favourites") {
                model.toggleCurrentFolderFavorite()
            }
            Divider()
            Button("Larger Thumbnails") { model.increaseGalleryThumbnailSize() }
                .disabled(model.viewMode != .gallery)
            Button("Smaller Thumbnails") { model.decreaseGalleryThumbnailSize() }
                .disabled(model.viewMode != .gallery)
            Button(model.isPreviewPaneVisible ? "Hide Preview Pane" : "Show Preview Pane") {
                model.togglePreviewPane()
            }
            Divider()
            Button(model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar") {
                model.toggleSidebar()
            }
            Divider()
            Button(model.verifyTransfers ? "Disable Transfer Verification" : "Verify Transfers") {
                model.toggleVerifyTransfers()
            }
            Button("Calculate Folder Sizes") { model.calculateVisibleFolderSizes() }
            Button("Calculate Selected Folder Sizes") { model.calculateSelectedFolderSizes() }
                .disabled(!model.selectedItems.contains(where: \.isDirectory))
            if model.isCalculatingFolderSizes {
                Button("Cancel Folder Size Calculation") { model.cancelFolderSizeCalculation() }
            }
            Button("Storage Usage…") { model.showStorageUsage() }
            Divider()
            Button("Command Palette…") { model.toggleCommandPalette() }
            Divider()
            Button("UU Explorer Settings…") {
                SettingsWindowController.shared.showSettings()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.toolbarText)
                .frame(width: 26, height: 26)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More actions")
    }

    private func sortButton(_ title: String, field: SortField) -> some View {
        Button {
            if model.sortField == field {
                model.setSort(field: field, ascending: !model.sortAscending)
            } else {
                model.setSort(field: field, ascending: true)
            }
        } label: {
            HStack {
                Text(title)
                if model.sortField == field {
                    Image(systemName: model.sortAscending ? "arrow.up" : "arrow.down")
                }
            }
        }
    }
}
