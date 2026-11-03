import AppKit
import ExplorerCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            favoritesSection
            if !model.favorites.isEmpty {
                Rectangle().fill(theme.sidebarDivider).frame(height: 1)
            }
            savedSearchesSection
            if !model.savedSearches.isEmpty {
                Rectangle().fill(theme.sidebarDivider).frame(height: 1)
            }
            Rectangle().fill(theme.sidebarDivider).frame(height: 1)
            networkSection
            quickAccessSection
            Rectangle().fill(theme.sidebarDivider).frame(height: 1)
            treeSection
        }
        .background(theme.sidebar)
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("NETWORK")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(theme.sidebarSecondary)
                Spacer()
                Button {
                    model.addNetworkLocation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.sidebarSecondary)
                .help("Add Network Share…")
            }
            .padding(.horizontal, 11)
            .padding(.top, 9)
            .padding(.bottom, 2)

            if model.networkLocations.isEmpty {
                Button {
                    model.addNetworkLocation()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("Add Network Share…")
                            .font(.system(size: 11.5))
                        Spacer()
                    }
                    .foregroundStyle(theme.sidebarSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 25)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(model.networkLocations) { location in
                    SidebarQuickRow(
                        item: QuickAccessItem(
                            title: location.name,
                            url: location.url ?? URL(fileURLWithPath: "/Volumes"),
                            symbol: "network",
                            color: theme.accent
                        ),
                        isSelected: false
                    ) {
                        model.connectNetworkLocation(location)
                    }
                    .contextMenu {
                        Button("Reconnect") { model.connectNetworkLocation(location) }
                        Button(location.autoConnect ? "Don’t Connect at Launch" : "Connect at Launch") {
                            model.toggleNetworkAutoConnect(location)
                        }
                        Button("Copy Address") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(location.urlString, forType: .string)
                        }
                        Button("Remove Network Location") { model.removeNetworkLocation(location) }
                    }
                }
            }
        }
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var savedSearchesSection: some View {
        if !model.savedSearches.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                sectionHeader("Saved Searches")
                ForEach(model.savedSearches) { search in
                    SidebarQuickRow(
                        item: QuickAccessItem(
                            title: search.name,
                            url: URL(fileURLWithPath: search.rootPath),
                            symbol: "magnifyingglass",
                            color: theme.accent
                        ),
                        isSelected: false
                    ) {
                        model.runSavedSearch(search)
                    }
                    .contextMenu {
                        Button("Run Search") { model.runSavedSearch(search) }
                        Button("Remove Saved Search") { model.removeSavedSearch(search) }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !model.favorites.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                sectionHeader("Favourites")
                ForEach(model.favorites, id: \.self) { url in
                    SidebarQuickRow(
                        item: QuickAccessItem(
                            title: favoriteTitle(url),
                            url: url,
                            symbol: "star.fill",
                            color: theme.accent
                        ),
                        isSelected: model.currentURL.path == url.path
                    ) {
                        model.go(to: url)
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        model.transfer(urls, to: url, copy: false)
                        return true
                    }
                    .contextMenu {
                        Button("Open in New Tab") { model.openInNewTab(url) }
                        Button("Open in Terminal") { model.openInTerminal(url) }
                        Button("Remove from Favourites") { model.toggleFavorite(url) }
                        Divider()
                        Button("Properties…") { PropertiesWindowController.show(for: url) }
                        Divider()
                        Button("UU Explorer Settings…") {
                            SettingsWindowController.shared.showSettings()
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func favoriteTitle(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            sectionHeader("Quick Access")
            ForEach(quickAccessItems) { item in
                SidebarQuickRow(
                    item: item,
                    isSelected: model.currentURL.path == item.url.path
                ) {
                    model.go(to: item.url)
                }
                .dropDestination(for: URL.self) { urls, _ in
                    model.transfer(urls, to: item.url, copy: false)
                    return true
                }
                .contextMenu {
                    Button("Open in New Tab") { model.openInNewTab(item.url) }
                    Button("Open in Terminal") { model.openInTerminal(item.url) }
                    Button(model.isFavorite(item.url) ? "Remove from Favourites" : "Pin to Favourites") {
                        model.toggleFavorite(item.url)
                    }
                    Divider()
                    Button("Properties…") { PropertiesWindowController.show(for: item.url) }
                    Divider()
                    Button("UU Explorer Settings…") {
                        SettingsWindowController.shared.showSettings()
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    private var treeSection: some View {
        VStack(spacing: 0) {
            sectionHeader("This Mac")
                .padding(.horizontal, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(treeRows) { row in
                            SidebarTreeRowView(
                                row: row,
                                isExpanded: model.isExpanded(row.url.path),
                                isSelected: model.currentURL.path == row.url.path
                            ) {
                                model.toggleExpanded(row.url.path)
                            } onSelect: {
                                model.go(to: row.url)
                                if !model.isExpanded(row.url.path) {
                                    model.toggleExpanded(row.url.path)
                                }
                            }
                            .dropDestination(for: URL.self) { urls, _ in
                                model.transfer(urls, to: row.url, copy: false)
                                return true
                            }
                            .contextMenu {
                                Button("Open in New Tab") { model.openInNewTab(row.url) }
                                Button("Open in Terminal") { model.openInTerminal(row.url) }
                                Button(model.isFavorite(row.url) ? "Remove from Favourites" : "Pin to Favourites") {
                                    model.toggleFavorite(row.url)
                                }
                                Divider()
                                Button("Properties…") { PropertiesWindowController.show(for: row.url) }
                                Divider()
                                Button("UU Explorer Settings…") {
                                    SettingsWindowController.shared.showSettings()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    scrollToCurrent(proxy, animated: false)
                }
                .onChange(of: model.currentURL) { _, _ in
                    scrollToCurrent(proxy, animated: true)
                }
                .onChange(of: model.treeRevealRequest) { _, request in
                    guard let request else { return }
                    scrollTo(request.path, proxy: proxy, animated: true)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, animated: Bool) {
        scrollTo(model.currentURL.path, proxy: proxy, animated: animated)
    }

    private func scrollTo(_ path: String, proxy: ScrollViewProxy, animated: Bool) {
        guard treeRows.contains(where: { $0.url.path == path }) else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.16)) {
                proxy.scrollTo(path, anchor: nil)
            }
        } else {
            proxy.scrollTo(path, anchor: nil)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(theme.sidebarSecondary)
            .padding(.leading, 8)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private var treeRows: [SidebarTreeRow] {
        var rows: [SidebarTreeRow] = []

        func append(
            url: URL,
            name: String,
            level: Int,
            isVolume: Bool,
            isInternal: Bool
        ) {
            let path = url.path
            let expanded = model.isExpanded(path)
            let loadedChildren = model.treeChildren[path]
            let hasChildren = isVolume || (loadedChildren.map { !$0.isEmpty } ?? true)

            rows.append(
                SidebarTreeRow(
                    url: url,
                    name: name,
                    level: level,
                    isVolume: isVolume,
                    isInternal: isInternal,
                    hasChildren: hasChildren
                )
            )

            guard expanded, let children = loadedChildren else { return }
            for child in children {
                append(
                    url: child.url,
                    name: child.name,
                    level: level + 1,
                    isVolume: false,
                    isInternal: true
                )
            }
        }

        for root in model.treeRoots {
            append(
                url: root.url,
                name: root.name,
                level: 0,
                isVolume: true,
                isInternal: root.isInternal
            )
        }
        return rows
    }

    private var quickAccessItems: [QuickAccessItem] {
        var items: [QuickAccessItem] = [
            QuickAccessItem(title: "Home", url: model.home, symbol: "house.fill", color: .blue)
        ]

        func append(
            _ directory: FileManager.SearchPathDirectory,
            title: String,
            symbol: String,
            color: Color
        ) {
            guard let url = FileManager.default.urls(for: directory, in: .userDomainMask).first,
                  FileManager.default.fileExists(atPath: url.path) else { return }
            items.append(
                QuickAccessItem(title: title, url: url.standardizedFileURL, symbol: symbol, color: color)
            )
        }

        append(.desktopDirectory, title: "Desktop", symbol: "desktopcomputer", color: .teal)
        append(.documentDirectory, title: "Documents", symbol: "doc.text.fill", color: .blue)
        append(.downloadsDirectory, title: "Downloads", symbol: "arrow.down.circle.fill", color: .green)
        let applications = URL(fileURLWithPath: "/Applications")
        if FileManager.default.fileExists(atPath: applications.path) {
            items.append(
                QuickAccessItem(
                    title: "Applications",
                    url: applications,
                    symbol: "square.grid.2x2.fill",
                    color: .indigo
                )
            )
        }
        append(.picturesDirectory, title: "Pictures", symbol: "photo.fill", color: .orange)
        return items
    }
}

private struct QuickAccessItem: Identifiable {
    let title: String
    let url: URL
    let symbol: String
    let color: Color

    var id: String { url.path }
}

private struct SidebarTreeRow: Identifiable {
    let url: URL
    let name: String
    let level: Int
    let isVolume: Bool
    let isInternal: Bool
    let hasChildren: Bool

    var id: String { url.path }
}

private struct SidebarQuickRow: View {
    let item: QuickAccessItem
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(item.color)
                    .frame(width: 16)
                Text(item.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.sidebarText)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 24)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.url.path)
    }

    private var backgroundColor: Color {
        if isSelected { return theme.accent.opacity(0.22) }
        if isHovering { return theme.sidebarHover }
        return .clear
    }
}

private struct SidebarTreeRowView: View {
    let row: SidebarTreeRow
    let isExpanded: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        HStack(spacing: 2) {
            Color.clear
                .frame(width: CGFloat(row.level) * 13, height: 1)

            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.sidebarSecondary)
                    .frame(width: 14, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(row.hasChildren ? 1 : 0)
            .disabled(!row.hasChildren)
            .help(row.hasChildren ? (isExpanded ? "Collapse" : "Expand") : "")

            Button(action: onSelect) {
                HStack(spacing: 5) {
                    if row.isVolume {
                        Image(systemName: row.isInternal ? "internaldrive" : "externaldrive")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.sidebarSecondary)
                            .frame(width: 15)
                    } else {
                        Image(nsImage: theme.folderIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 15, height: 15)
                    }
                    Text(row.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.sidebarText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(row.url.path)
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundColor)
        )
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return theme.accent.opacity(0.22) }
        if isHovering { return theme.sidebarHover }
        return .clear
    }
}
