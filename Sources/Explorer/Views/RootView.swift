import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var tabs: TabManager
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var thumbnails = ThumbnailStore()

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(model: model)
                .zIndex(50)
            Rectangle().fill(theme.divider).frame(height: 1)
            TabBarView(model: model, tabs: tabs)
            Rectangle().fill(theme.divider).frame(height: 1)

            HStack(spacing: 0) {
                if model.isSidebarVisible {
                    SidebarView(model: model)
                        .frame(width: model.sidebarWidth)
                    SidebarDividerView(model: model)
                }

                FileContentView(model: model, thumbnails: thumbnails)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if model.isPreviewPaneVisible {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1)
                    PreviewPaneView(model: model, thumbnails: thumbnails)
                        .frame(width: 320)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(theme.divider).frame(height: 1)
            StatusBarView(model: model)
        }
        .background(theme.background)
        .tint(theme.accent)
        .overlay(alignment: .bottomTrailing) {
            OperationQueueOverlay(queue: model.operations)
                .padding(.trailing, 16)
                .padding(.bottom, 46)
        }
        .overlay {
            if model.isCommandPaletteVisible {
                CommandPaletteView(model: model)
            }
        }
        .sheet(item: $model.nameEditor) { _ in
            NameEditorView(model: model)
        }
        .sheet(item: $model.batchRename) { session in
            BatchRenameView(model: model, session: session)
        }
        .sheet(item: $model.encryptedZip) { request in
            EncryptedZipView(model: model, request: request)
        }
        .sheet(item: $model.archiveBrowser) { request in
            ArchiveBrowserView(archive: request.archive)
        }
        .sheet(isPresented: $model.isManagingCustomActions) {
            CustomActionManagerView(model: model)
        }
        .sheet(isPresented: $model.isAddingNetworkLocation) {
            NetworkShareWizardView(model: model)
        }
        .sheet(isPresented: $model.isShowingStorageUsage) {
            StorageUsageView(model: model)
        }
    }
}

struct FileContentView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var thumbnails: ThumbnailStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        ZStack {
            if model.viewMode == .details {
                FileTableView(model: model)
            } else {
                GalleryView(model: model, thumbnails: thumbnails)
            }

            if model.displayedItems.isEmpty {
                emptyContent
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.content)
    }

    @ViewBuilder
    private var emptyContent: some View {
        if model.isSearching {
            VStack(spacing: 9) {
                ProgressView()
                    .controlSize(.large)
                Text(model.searchScanned > 0
                    ? "Searching… \(model.searchScanned.formatted()) items scanned"
                    : "Searching…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.contentSecondary)
                Button("Stop Search") { model.clearSearch() }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
            }
        } else if model.isLoading {
            ProgressView()
                .controlSize(.large)
        } else if let error = model.loadError {
            EmptyFolderView(
                symbol: "exclamationmark.triangle",
                title: "Can’t open this folder",
                message: error
            )
        } else if model.items.isEmpty {
            EmptyFolderView(
                symbol: "folder",
                title: "This folder is empty",
                message: "Right-click here to create a folder or file."
            )
        } else {
            EmptyFolderView(
                symbol: "doc.text.magnifyingglass",
                title: "No matching items",
                message: "No items match “\(model.filterText)”."
            )
        }
    }
}

private struct EmptyFolderView: View {
    let symbol: String
    let title: String
    let message: String
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 9) {
            if symbol == "folder" {
                Image(nsImage: theme.folderIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 52, height: 52)
                    .opacity(0.8)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(theme.contentSecondary.opacity(0.65))
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.contentText.opacity(0.8))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.contentSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .padding(24)
    }
}


private struct SidebarDividerView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var dragStartWidth: CGFloat?

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.divider.opacity(isHovering ? 1 : 0.7))
                .frame(width: 1)
            Color.clear
                .contentShape(Rectangle())
        }
        .frame(width: 5)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = model.sidebarWidth
                    }
                    model.setSidebarWidth((dragStartWidth ?? model.sidebarWidth) + value.translation.width)
                }
                .onEnded { _ in
                    dragStartWidth = nil
                }
        )
    }
}
