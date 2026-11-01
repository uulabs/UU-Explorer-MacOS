import AppKit
import ExplorerCore
import QuickLookUI
import SwiftUI

struct PreviewPaneView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var thumbnails: ThumbnailStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.contentSecondary)
                Text("Preview")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.contentText)
                Spacer(minLength: 4)
                if let item = model.selectedItems.first {
                    Text(item.name)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.contentSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(item.url.path)
                }
                Button {
                    model.togglePreviewPane()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.contentSecondary)
                .help("Hide preview pane")
                .accessibilityLabel("Hide preview pane")
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(theme.contentField)

            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)

            if let item = model.selectedItems.first {
                preview(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Preview of \(item.name)")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(theme.contentSecondary.opacity(0.65))
                    Text("Select a file to preview")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.contentSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.content)
    }

    @ViewBuilder
    private func preview(for item: FileItem) -> some View {
        if item.isDirectory {
            VStack(spacing: 14) {
                Image(nsImage: theme.folderIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                VStack(spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(theme.contentText)
                        .multilineTextAlignment(.center)
                    Text("Folder")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.contentSecondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if item.isImage {
            PreviewImage(item: item, thumbnails: thumbnails)
        } else {
            QuickLookPreview(url: item.url)
        }
    }
}

private struct PreviewImage: View {
    let item: FileItem
    @ObservedObject var thumbnails: ThumbnailStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Group {
            if let image = thumbnails.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(12)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.contentField.opacity(0.35))
        .task(id: thumbnails.key(for: item)) {
            thumbnails.request(for: item)
        }
    }
}

private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        let current = view.previewItem as? URL
        if current?.standardizedFileURL != url.standardizedFileURL {
            view.previewItem = url as NSURL
        }
    }
}
