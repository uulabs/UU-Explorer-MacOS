import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @ObservedObject var model: ExplorerModel
    @ObservedObject var tabs: TabManager
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoveredTabID: UUID?

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs.tabs) { tab in
                            tabChip(tab)
                                .id(tab.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: tabs.activeTabID) { _, id in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Button {
                tabs.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.toolbarText.opacity(0.8))
            .help("New tab (⌘T)")
            .accessibilityLabel("New tab")
        }
        .padding(.horizontal, 8)
        .frame(height: 34)
        .background(theme.toolbar)
    }

    private func tabChip(_ tab: ExplorerTab) -> some View {
        let isActive = tabs.activeTabID == tab.id
        let isHovered = hoveredTabID == tab.id

        return HStack(spacing: 5) {
            Image(nsImage: theme.folderIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 14, height: 14)

            Text(tab.title)
                .font(.system(size: 11.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? theme.toolbarText : theme.toolbarText.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                tabs.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.toolbarText.opacity(0.62))
            .opacity(isActive || isHovered ? 1 : 0)
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close tab")
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 94, maxWidth: 210, minHeight: 24, maxHeight: 24)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? theme.content : (isHovered ? theme.contentField.opacity(0.7) : Color.clear))
        )
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(theme.accent)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            tabs.selectTab(tab.id)
        }
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : (hoveredTabID == tab.id ? nil : hoveredTabID)
        }
        .contextMenu {
            Button("New Tab") { tabs.newTab() }
            Button("Close Tab") { tabs.closeTab(tab.id) }
        }
        .onDrag {
            NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.transfer(
                urls,
                to: URL(fileURLWithPath: tab.state.path),
                copy: false
            )
            return true
        }
        .onDrop(of: [UTType.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let value = object as? String,
                      let id = UUID(uuidString: value) else { return }
                Task { @MainActor in
                    tabs.moveTab(id, before: tab.id)
                }
            }
            return true
        }
        .help(tab.state.path)
    }
}
