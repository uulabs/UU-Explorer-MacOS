import AppKit
import ExplorerCore
import SwiftUI

struct GalleryView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var thumbnails: ThumbnailStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectionAnchor: String?
    @State private var hoveredID: String?

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            galleryControls
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(
                            .adaptive(
                                minimum: model.galleryThumbnailSize,
                                maximum: model.galleryThumbnailSize + 64
                            ),
                            spacing: 14
                        )],
                        alignment: .leading,
                        spacing: 16
                    ) {
                        ForEach(model.displayedItems) { item in
                            GalleryCell(
                                item: item,
                                theme: theme,
                                thumbnail: thumbnails.image(for: item),
                                isSelected: model.selection.contains(item.id),
                                isHovering: hoveredID == item.id
                            )
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    hoveredID = item.id
                                } else if hoveredID == item.id {
                                    hoveredID = nil
                                }
                            }
                            .gesture(
                                TapGesture(count: 2).onEnded {
                                    model.open(item)
                                }
                            )
                            .simultaneousGesture(
                                TapGesture(count: 1).onEnded {
                                    select(item)
                                }
                            )
                            .contextMenu {
                                contextMenu(for: item)
                            }
                            .dropDestination(for: URL.self) { urls, _ in
                                guard item.isDirectory else { return false }
                                model.transfer(urls, to: item.url, copy: false)
                                return true
                            }
                            .onDrag {
                                NSItemProvider(object: item.url as NSURL)
                            }
                            .id(item.id)
                            .help(item.url.path)
                            .task(id: thumbnails.key(for: item)) {
                                thumbnails.request(for: item)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(item.name)
                            .accessibilityAddTraits(.isButton)
                        }
                    }
                    .padding(18)
                }
                .onChange(of: model.selection) { _, selection in
                    guard let id = selection.first else { return }
                    withAnimation(.easeInOut(duration: 0.14)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .background(theme.content)
        .dropDestination(for: URL.self) { urls, _ in
            model.transfer(urls, to: model.currentURL, copy: false)
            return true
        }
        .contextMenu {
            Button("Paste") { model.pasteFiles() }
                .disabled(!model.canPaste)
            Divider()
            Button("New Folder") { model.beginNewFolder() }
            Button("New File") { model.beginNewFile() }
            Button("Open in Terminal") { model.openCurrentFolderInTerminal() }
            Divider()
            Button("Refresh") { model.refresh() }
            Button(model.currentFolderIsFavorite ? "Remove Current Folder from Favourites" : "Pin Current Folder to Favourites") {
                model.toggleCurrentFolderFavorite()
            }
            Button("Show in Finder") { model.revealSelectionInFinder() }
                .disabled(model.selection.isEmpty)
            Button("UU Explorer Settings…") {
                SettingsWindowController.shared.showSettings()
            }
        }
        .onAppear {
            DispatchQueue.main.async {
                releaseTextFocus()
            }
        }
    }

    private var galleryControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.contentSecondary)
            Text("Thumbnail Size")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.contentSecondary)

            Spacer(minLength: 12)

            Button {
                model.decreaseGalleryThumbnailSize()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.contentText)
            .help("Smaller thumbnails (⌘-)")
            .accessibilityLabel("Smaller thumbnails")

            Slider(
                value: Binding(
                    get: { Double(model.galleryThumbnailSize) },
                    set: { model.setGalleryThumbnailSize(CGFloat($0)) }
                ),
                in: 110...220,
                step: 8
            )
            .controlSize(.small)
            .frame(width: 126)
            .accessibilityLabel("Gallery thumbnail size")

            Button {
                model.increaseGalleryThumbnailSize()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.contentText)
            .help("Larger thumbnails (⌘+)")
            .accessibilityLabel("Larger thumbnails")

            Text("\(Int(model.galleryThumbnailSize)) px")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(theme.contentSecondary)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(theme.contentField)
    }

    private func select(_ item: FileItem) {
        releaseTextFocus()
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift), let anchor = selectionAnchor {
            model.selectRange(in: model.displayedItems, from: anchor, to: item)
        } else if flags.contains(.command) {
            model.toggleSelection(item)
            selectionAnchor = item.id
        } else {
            model.selectOnly(item)
            selectionAnchor = item.id
        }
    }

    private func prepareContextSelection(_ item: FileItem) {
        if !model.selection.contains(item.id) {
            model.selection = [item.id]
        }
    }

    private func releaseTextFocus() {
        guard let window = NSApp.keyWindow,
              let responder = window.firstResponder,
              responder is NSTextView || (responder is NSControl && !(responder is NSTableView)) else {
            return
        }
        window.makeFirstResponder(nil)
    }

    @ViewBuilder
    private func contextMenu(for item: FileItem) -> some View {
        Button("Open") {
            prepareContextSelection(item)
            model.openSelectedItems()
        }
        if item.isDirectory {
            Button("Open in New Tab") {
                model.openInNewTab(item.url)
            }
            Button("Open in Terminal") {
                model.openInTerminal(item.url)
            }
        }
        Button("Quick Look") {
            prepareContextSelection(item)
            model.quickLookSelection()
        }
        Button("Show in Details") {
            prepareContextSelection(item)
            model.setViewMode(.details)
        }
        Divider()
        Button("Show in Finder") {
            prepareContextSelection(item)
            model.revealSelectionInFinder()
        }
        Button("Cut") {
            prepareContextSelection(item)
            model.copySelectionToPasteboard(cut: true)
        }
        Button("Copy") {
            prepareContextSelection(item)
            model.copySelectionToPasteboard()
        }
        if item.isDirectory {
            Button("Paste Into Folder") {
                model.pasteFiles(into: item.url)
            }
            .disabled(!model.canPaste)
        }
        Divider()
        Button("Copy Path") {
            prepareContextSelection(item)
            model.copySelectionPath()
        }
        Menu("Copy Path As") {
            ForEach(PathCopyFormat.allCases) { format in
                Button(format.title) {
                    prepareContextSelection(item)
                    model.copySelectionPath(as: format)
                }
            }
        }
        Menu("Custom Actions") {
            ForEach(model.customActions.filter(\.isEnabled)) { action in
                Button(action.name.isEmpty ? "Untitled Action" : action.name) {
                    prepareContextSelection(item)
                    model.runCustomAction(action)
                }
            }
            if !model.customActions.isEmpty { Divider() }
            Button("Manage Custom Actions…") { model.beginCustomActionManager() }
        }
        if item.isDirectory {
            Button(model.isFavorite(item.url) ? "Remove from Favourites" : "Pin to Favourites") {
                model.toggleFavorite(item.url)
            }
        }
        Button("Compress") {
            prepareContextSelection(item)
            model.compressSelection()
        }
        Button("Compress with Password…") {
            model.selection = [item.id]
            model.beginEncryptedCompression()
        }
        if ArchiveService.isArchive(item.url) {
            Button("Browse Archive…") {
                model.selection = [item.id]
                model.beginArchiveBrowsing()
            }
            Button("Extract Here") {
                prepareContextSelection(item)
                model.extractSelectionHere()
            }
            Button("Extract To…") {
                prepareContextSelection(item)
                model.extractSelection()
            }
        }
        Divider()
        Button("New Folder") { model.beginNewFolder() }
        Button("New File") { model.beginNewFile() }
        Divider()
        Button("Rename…") {
            model.selection = [item.id]
            model.beginRenameSelected()
        }
        Button("Batch Rename…") {
            prepareContextSelection(item)
            model.beginBatchRename()
        }
        let applications = model.openWithApplications(for: item.url)
        if !applications.isEmpty {
            Menu("Open With") {
                ForEach(applications) { application in
                    Button {
                        prepareContextSelection(item)
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
            Button("Duplicate") {
                prepareContextSelection(item)
                model.duplicateSelection()
            }
            Button("Create Symbolic Link") {
                prepareContextSelection(item)
                model.createLinkSelection()
            }
            Button("Share…") {
                prepareContextSelection(item)
                model.shareSelection()
            }
            Divider()
            Button("Copy Path") {
                prepareContextSelection(item)
                model.copySelectionPath()
            }
            Button("Show in Finder") {
                prepareContextSelection(item)
                model.revealSelectionInFinder()
            }
        }
        if item.isDirectory {
            Button("Calculate Size") {
                model.selection = [item.id]
                model.calculateSelectedFolderSizes()
            }
        }
        Button("Move to Trash") {
            prepareContextSelection(item)
            model.moveSelectionToTrash()
        }
        Button("Properties…") {
            model.selection = [item.id]
            model.showProperties()
        }
        Divider()
        Button("UU Explorer Settings…") {
            SettingsWindowController.shared.showSettings()
        }
    }
}

private struct GalleryCell: View {
    let item: FileItem
    let theme: ResolvedTheme
    let thumbnail: NSImage?
    let isSelected: Bool
    let isHovering: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(theme.contentField)

                    if item.isDirectory {
                        Image(nsImage: theme.folderIcon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 62, height: 62)
                    } else if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    } else if item.isImage {
                        Image(systemName: "photo")
                            .font(.system(size: 27, weight: .light))
                            .foregroundStyle(theme.contentSecondary)
                    } else {
                        Image(nsImage: AppIcons.icon(
                            for: item,
                            folderColor: theme.folderRGB,
                            folderStyle: theme.folderIconStyle
                        ))
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? theme.accent : Color.clear, lineWidth: 2)
                )
            }
            .aspectRatio(1, contentMode: .fit)

            Text(item.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(theme.contentText)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Text(item.isDirectory ? "Folder" : item.kind)
                    .lineLimit(1)
                Spacer(minLength: 2)
                if !item.isDirectory {
                    Text(ByteFormat.string(item.byteSize))
                        .monospacedDigit()
                }
            }
            .font(.system(size: 9.5))
            .foregroundStyle(theme.contentSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? theme.accent.opacity(0.14) : (isHovering ? theme.hover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? theme.accent.opacity(0.75) : (isHovering ? theme.divider : Color.clear),
                    lineWidth: 1
                )
        )
    }
}
