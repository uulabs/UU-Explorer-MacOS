import ExplorerCore
import SwiftUI

struct StatusBarView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        HStack(spacing: 9) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
            }

            Text(itemCountText)
                .foregroundStyle(theme.toolbarSecondary)

            if model.isCalculatingFolderSizes {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.8)
                Text("Sizing \(model.folderSizeDone) of \(model.folderSizeTotal)")
                    .foregroundStyle(theme.toolbarSecondary)
            }

            if let status = model.status {
                statusView(status)
            }

            Spacer(minLength: 16)

            selectionView

            if model.volume != nil {
                Rectangle()
                    .fill(theme.toolbarDivider)
                    .frame(width: 1, height: 12)
                Text(volumeText)
                    .foregroundStyle(theme.toolbarSecondary)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(theme.toolbarText)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(theme.toolbar)
    }

    private var itemCountText: String {
        if model.isRecursiveSearchActive {
            let count = model.displayedItems.count
            return "\(count) result\(count == 1 ? "" : "s")"
        }
        if model.isFiltering {
            return "\(model.displayedItems.count) of \(model.items.count) items"
        }
        let count = model.items.count
        return "\(count) \(count == 1 ? "item" : "items")"
    }

    private var volumeText: String {
        guard let volume = model.volume else { return "" }
        if let available = volume.availableCapacity, let total = volume.totalCapacity {
            return "\(ByteFormat.string(available)) free of \(ByteFormat.string(total))"
        }
        return volume.name
    }

    @ViewBuilder
    private func statusView(_ status: ExplorerStatus) -> some View {
        Label {
            Text(status.text)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Image(systemName: status.kind == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        }
        .foregroundStyle(status.kind == .error ? Color.red : theme.toolbarSecondary)
        .help(status.text)
    }

    @ViewBuilder
    private var selectionView: some View {
        let selected = model.selectedItems

        if selected.isEmpty {
            Text("No selection")
                .foregroundStyle(theme.toolbarSecondary)
        } else if selected.count == 1, let item = selected.first {
            HStack(spacing: 5) {
                Image(nsImage: AppIcons.icon(
                    for: item,
                    folderColor: theme.folderRGB,
                    folderStyle: theme.folderIconStyle
                ))
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 320, alignment: .leading)
                Text("·")
                    .foregroundStyle(theme.toolbarText.opacity(0.4))
                Text(selectionSizeText(item))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .help(selectionSizeHelp(item))
            }
            .help(item.url.path)
        } else {
            HStack(spacing: 5) {
                Text("\(selected.count) items selected")
                    .foregroundStyle(theme.toolbarSecondary)
                Text("·")
                    .foregroundStyle(theme.toolbarText.opacity(0.4))
                Text(selectionBreakdown)
                Text("·")
                    .foregroundStyle(theme.toolbarText.opacity(0.4))
                Text(ByteFormat.string(model.selectedByteCount))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
    }

    private func selectionSizeText(_ item: FileItem) -> String {
        if !item.isDirectory {
            return ByteFormat.string(item.byteSize)
        }
        if let size = model.folderSizes[item.url.path] {
            return ByteFormat.string(size.bytes)
        }
        if model.calculatingFolderPaths.contains(item.url.path) {
            return "Calculating…"
        }
        return "Folder"
    }

    private func selectionSizeHelp(_ item: FileItem) -> String {
        if !item.isDirectory {
            return item.byteSize.map(ByteFormat.exact) ?? ""
        }
        if let size = model.folderSizes[item.url.path] {
            return "\(ByteFormat.exact(size.bytes)) — \(size.fileCount) files, \(size.directoryCount) folders"
        }
        return item.url.path
    }

    private var selectionBreakdown: String {
        let files = model.selectedFileCount
        let folders = model.selectedFolderCount
        if files > 0 && folders > 0 {
            return "\(files) \(files == 1 ? "file" : "files"), \(folders) \(folders == 1 ? "folder" : "folders")"
        }
        if folders > 0 {
            return "\(folders) \(folders == 1 ? "folder" : "folders")"
        }
        return "\(files) \(files == 1 ? "file" : "files")"
    }
}
