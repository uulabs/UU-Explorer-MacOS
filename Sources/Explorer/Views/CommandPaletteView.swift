import ExplorerCore
import SwiftUI

private struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let enabled: Bool
    let action: () -> Void
}

struct CommandPaletteView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    private var commands: [PaletteCommand] {
        let hasSelection = !model.selection.isEmpty
        let hasFolders = model.selectedItems.contains(where: \.isDirectory)
        let base: [PaletteCommand] = [
            command("new-folder", "New Folder", "Create a folder here", "folder.badge.plus") {
                model.beginNewFolder()
            },
            command("new-file", "New File", "Create an empty file here", "doc.badge.plus") {
                model.beginNewFile()
            },
            command("open", "Open", "Open the selected items", "arrow.up.forward.app", enabled: hasSelection) {
                model.openSelectedItems()
            },
            command("terminal", "Open in Terminal", "Open the current folder in Terminal", "terminal") {
                model.openCurrentFolderInTerminal()
            },
            command("quick-look", "Quick Look", "Preview the current selection", "eye", enabled: hasSelection) {
                model.quickLookSelection()
            },
            command("rename", "Rename…", "Rename the selected item", "pencil", enabled: model.selection.count == 1) {
                model.beginRenameSelected()
            },
            command("batch-rename", "Batch Rename…", "Rename the selection with a pattern", "character.cursor.ibeam", enabled: hasSelection) {
                model.beginBatchRename()
            },
            command("duplicate", "Duplicate", "Copy the selection beside itself", "plus.square.on.square", enabled: hasSelection) {
                model.duplicateSelection()
            },
            command("link", "Create Symbolic Link", "Create a link to the selection", "link", enabled: hasSelection) {
                model.createLinkSelection()
            },
            command("share", "Share…", "Share the selection", "square.and.arrow.up", enabled: hasSelection) {
                model.shareSelection()
            },
            command("verify-transfers", model.verifyTransfers ? "Disable Transfer Verification" : "Verify Transfers", "Compare copied data with SHA-256", "checkmark.shield") {
                model.toggleVerifyTransfers()
            },
            command("copy", "Copy", "Copy the selection", "doc.on.doc", enabled: hasSelection) {
                model.copySelectionToPasteboard()
            },
            command("cut", "Cut", "Cut the selection", "scissors", enabled: hasSelection) {
                model.copySelectionToPasteboard(cut: true)
            },
            command("paste", "Paste", "Paste into this folder", "doc.on.clipboard", enabled: model.canPaste) {
                model.pasteFiles()
            },
            command("trash", "Move to Trash", "Move the selection to Trash", "trash", enabled: hasSelection) {
                model.moveSelectionToTrash()
            },
            command("copy-path", "Copy Path", "Copy the selected path", "link.badge.plus", enabled: hasSelection) {
                model.copySelectionPath()
            },
            command("reveal", "Show in Finder", "Reveal the selection in Finder", "folder", enabled: hasSelection) {
                model.revealSelectionInFinder()
            },
            command("browse-archive", "Browse Archive…", "Inspect and selectively extract archive contents", "archivebox", enabled: model.selectedItems.count == 1 && model.selectedItems.first.map { ArchiveService.isArchive($0.url) } == true) {
                model.beginArchiveBrowsing()
            },
            command("find-large-files", "Find Large Files", "Search recursively for files over 100 MB", "externaldrive.badge.questionmark") {
                model.findLargeFiles()
            },
            command("folder-size", "Calculate Folder Sizes", "Measure visible folders", "externaldrive") {
                model.calculateVisibleFolderSizes()
            },
            command("folder-size-selection", "Calculate Selected Sizes", "Measure selected folders", "externaldrive.fill.badge.checkmark", enabled: hasFolders) {
                model.calculateSelectedFolderSizes()
            },
            command("storage", "Storage Usage…", "Show volume and current-folder usage", "chart.pie") {
                model.showStorageUsage()
            },
            command("details", "Details View", "Switch to the list view", "list.bullet") {
                model.setViewMode(.details)
            },
            command("gallery", "Gallery View", "Switch to the gallery view", "square.grid.2x2") {
                model.setViewMode(.gallery)
            },
            command("hidden", model.showHidden ? "Hide Hidden Files" : "Show Hidden Files", "Toggle hidden files", "eye.slash") {
                model.toggleHiddenFiles()
            },
            command("refresh", "Refresh", "Reload the current folder", "arrow.clockwise") {
                model.refresh()
            },
            command("sidebar", model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar", "Toggle the sidebar", "sidebar.left") {
                model.toggleSidebar()
            },
            command("preview", model.isPreviewPaneVisible ? "Hide Preview Pane" : "Show Preview Pane", "Toggle the preview pane", "rectangle.righthalf.inset.filled") {
                model.togglePreviewPane()
            },
            command("save-search", "Save Search", "Save the current query and folder", "bookmark", enabled: !model.filterText.isEmpty) {
                model.saveCurrentSearch()
            },
            command("settings", "UU Explorer Settings…", "Open settings", "gearshape") {
                SettingsWindowController.shared.showSettings()
            }
        ]
        let customActions = model.customActions.filter(\.isEnabled).map { action in
            command(
                "custom-\(action.id.uuidString)",
                action.name.isEmpty ? "Untitled Action" : action.name,
                "Run custom action",
                "terminal",
                enabled: action.scope == .currentFolder || hasSelection
            ) {
                model.runCustomAction(action)
            }
        }
        return base + customActions + [
            command("manage-custom-actions", "Manage Custom Actions…", "Add, edit, or remove shell actions", "slider.horizontal.3") {
                model.beginCustomActionManager()
            }
        ]
    }

    private var filteredCommands: [PaletteCommand] {
        let available = commands.filter(\.enabled)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return available }
        return available.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
                $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var clampedIndex: Int {
        guard !filteredCommands.isEmpty else { return 0 }
        return min(selectedIndex, filteredCommands.count - 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { model.closeCommandPalette() }

            VStack(spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "command")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    TextField("Type a command…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($searchFocused)
                        .onSubmit { executeSelected() }
                        .onExitCommand { model.closeCommandPalette() }
                        .onKeyPress(.downArrow) {
                            moveSelection(by: 1)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            moveSelection(by: -1)
                            return .handled
                        }
                    Text("⌘K")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.contentSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.contentField, in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)

                Divider()

                if filteredCommands.isEmpty {
                    VStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18))
                        Text("No commands found")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(theme.contentSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                                    commandRow(command, index: index)
                                        .id(command.id)
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 390)
                        .onChange(of: clampedIndex) { _, index in
                            guard filteredCommands.indices.contains(index) else { return }
                            proxy.scrollTo(filteredCommands[index].id, anchor: .center)
                        }
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Text("↑↓ Navigate")
                    Text("↵ Run")
                    Text("esc Close")
                    Spacer()
                    Text("\(filteredCommands.count) commands")
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.contentSecondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
            }
            .frame(width: 620)
            .background(theme.content, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 22, y: 10)
            .padding(.top, 80)
        }
        .onAppear {
            selectedIndex = 0
            DispatchQueue.main.async {
                searchFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    private func command(
        _ id: String,
        _ title: String,
        _ subtitle: String,
        _ symbol: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> PaletteCommand {
        PaletteCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            enabled: enabled,
            action: action
        )
    }

    private func commandRow(_ command: PaletteCommand, index: Int) -> some View {
        let selected = index == clampedIndex
        return HStack(spacing: 10) {
            Image(systemName: command.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? theme.accent : theme.contentSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(theme.contentText)
                Text(command.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.contentSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            selected ? theme.accent.opacity(0.14) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedIndex = index
            executeSelected()
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filteredCommands.isEmpty else { return }
        selectedIndex = min(max(clampedIndex + delta, 0), filteredCommands.count - 1)
    }

    private func executeSelected() {
        guard filteredCommands.indices.contains(clampedIndex) else { return }
        let action = filteredCommands[clampedIndex].action
        model.closeCommandPalette()
        action()
    }
}
