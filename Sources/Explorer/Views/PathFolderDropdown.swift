import AppKit
import ExplorerCore
import SwiftUI

struct PathFolderDropdown: View {
    @ObservedObject var model: ExplorerModel
    let rootURL: URL
    var symbol = "chevron.down"
    var compact = false
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPresented = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: compact ? 10 : 11, weight: .medium))
                .foregroundStyle(theme.toolbarSecondary)
                .frame(width: compact ? 14 : 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Browse parent and child folders")
        .accessibilityLabel(compact ? "Browse parent and child folders" : "Browse folder tree")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            PathFolderTree(rootURL: rootURL, includeHidden: model.showHidden) { url in
                isPresented = false
                model.navigate(to: url)
            }
            .environmentObject(themeStore)
            .id(rootURL.path + String(model.showHidden))
        }
        .onChange(of: model.currentURL) { _, _ in isPresented = false }
    }
}

@MainActor
private final class FolderBrowserModel: ObservableObject {
    let rootURL: URL
    let includeHidden: Bool
    @Published var children: [String: [DirectoryEntry]] = [:]
    @Published var expanded: Set<String>
    @Published var loading: Set<String> = []
    @Published var errors: [String: String] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    init(rootURL: URL, includeHidden: Bool) {
        self.rootURL = rootURL.standardizedFileURL
        self.includeHidden = includeHidden
        self.expanded = [rootURL.standardizedFileURL.path]
    }

    func toggle(_ url: URL) {
        if expanded.contains(url.path) {
            expanded.remove(url.path)
        } else {
            expanded.insert(url.path)
            load(url)
        }
    }

    func load(_ url: URL) {
        let path = url.path
        guard children[path] == nil, !loading.contains(path) else { return }
        errors[path] = nil
        loading.insert(path)
        let includeHidden = includeHidden
        tasks[path] = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FileSystemService.folderChildren(at: url, includeHidden: includeHidden) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.loading.remove(path)
            self.tasks[path] = nil
            switch result {
            case .success(let entries): self.children[path] = entries
            case .failure(let error): self.errors[path] = error.localizedDescription
            }
        }
    }

    func refresh() {
        cancel()
        children = [:]
        errors = [:]
        expanded = [rootURL.path]
        load(rootURL)
    }

    func cancel() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        loading.removeAll()
    }
}

private struct FolderBrowserNode: Identifiable {
    let url: URL
    let name: String
    let depth: Int
    var id: String { url.path }
}

private struct PathFolderTree: View {
    @StateObject private var browser: FolderBrowserModel
    let navigate: (URL) -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    init(rootURL: URL, includeHidden: Bool, navigate: @escaping (URL) -> Void) {
        _browser = StateObject(wrappedValue: FolderBrowserModel(rootURL: rootURL, includeHidden: includeHidden))
        self.navigate = navigate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Browse folders")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.backgroundText)
                Spacer()
                if browser.rootURL.path != "/" {
                    Button {
                        navigate(browser.rootURL.deletingLastPathComponent())
                    } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).help("Open enclosing folder")
                    .accessibilityLabel("Open enclosing folder")
                }
                Button { browser.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh folders")
                    .accessibilityLabel("Refresh folders")
            }
            .foregroundStyle(theme.backgroundText)
            .padding(12)
            Rectangle().fill(theme.divider).frame(height: 1)

            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    if !parentFolders.isEmpty {
                        Text("PARENT FOLDERS")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.backgroundText.opacity(0.62))
                            .padding(.leading, 8)
                            .padding(.top, 5)
                            .padding(.bottom, 2)
                        ForEach(parentFolders) { node in
                            parentRow(node)
                        }
                        Rectangle()
                            .fill(theme.divider)
                            .frame(height: 1)
                            .padding(.vertical, 4)
                    }

                    ForEach(nodes) { node in
                        folderRow(node)
                        if browser.expanded.contains(node.id) {
                            if browser.loading.contains(node.id) {
                                HStack(spacing: 7) {
                                    ProgressView().controlSize(.mini)
                                    Text("Loading folders…").foregroundStyle(theme.backgroundText.opacity(0.62))
                                }
                                .font(.system(size: 11))
                                .padding(.leading, indent(node.depth + 1) + 24).padding(.vertical, 5)
                            } else if let error = browser.errors[node.id] {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Can’t read this folder").fontWeight(.medium)
                                    Text(error).foregroundStyle(theme.backgroundText.opacity(0.62)).lineLimit(3)
                                    Button("Try again") { browser.load(node.url) }
                                        .buttonStyle(.link)
                                }
                                .font(.system(size: 11)).frame(maxWidth: 330, alignment: .leading)
                                .padding(.leading, indent(node.depth + 1) + 24).padding(.vertical, 5)
                            } else if browser.children[node.id]?.isEmpty == true {
                                Text("No subfolders").font(.system(size: 11)).foregroundStyle(theme.backgroundText.opacity(0.62))
                                    .padding(.leading, indent(node.depth + 1) + 24).padding(.vertical, 5)
                            }
                        }
                    }
                }
                .padding(6).frame(minWidth: 428, alignment: .leading)
            }
            .frame(height: 320)
            Rectangle().fill(theme.divider).frame(height: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Parent folders appear above. Expand arrows to browse; click a folder name to open it.")
                Text(browser.rootURL.path).lineLimit(1).truncationMode(.middle).help(browser.rootURL.path)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(theme.backgroundText.opacity(0.62))
            .padding(10)
        }
        .frame(width: 440)
        .background(theme.background)
        .onAppear { browser.load(browser.rootURL) }
        .onDisappear { browser.cancel() }
    }

    private var parentFolders: [FolderBrowserNode] {
        var result: [FolderBrowserNode] = []
        var cursor = browser.rootURL.standardizedFileURL
        while result.count < 6 {
            let parent = cursor.deletingLastPathComponent().standardizedFileURL
            if parent.path == cursor.path { break }
            result.append(FolderBrowserNode(
                url: parent,
                name: displayName(for: parent),
                depth: 0
            ))
            cursor = parent
        }
        return result
    }

    private func displayName(for url: URL) -> String {
        if url.path == "/" {
            return FileSystemService.volumeInfo(for: url)?.name ?? "Macintosh HD"
        }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? url.lastPathComponent : name
    }

    private func parentRow(_ node: FolderBrowserNode) -> some View {
        Button {
            navigate(node.url)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 16)
                Text(node.name)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.backgroundText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text("Parent")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.backgroundText.opacity(0.62))
            }
            .frame(height: 25)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(node.url.path)
        .accessibilityLabel("Open parent folder \(node.name)")
    }

    private func folderRow(_ node: FolderBrowserNode) -> some View {
        let expanded = browser.expanded.contains(node.id)
        let empty = browser.children[node.id]?.isEmpty == true
        return HStack(spacing: 3) {
            Button { browser.toggle(node.url) } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.backgroundText.opacity(0.62)).frame(width: 22, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(empty)
            .opacity(empty ? 0.25 : 1)
            .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(node.name)")
            Button { navigate(node.url) } label: {
                HStack(spacing: 7) {
                    Image(nsImage: theme.folderIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                    Text(node.name)
                        .font(.system(size: 12, weight: node.depth == 0 ? .semibold : .regular))
                        .foregroundStyle(theme.backgroundText)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                }
                .frame(height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(node.url.path)
            .accessibilityLabel("Open \(node.name)")
        }
        .padding(.leading, indent(node.depth))
        .padding(.trailing, 6)
        .background(node.depth == 0 ? theme.accent.opacity(0.11) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4))
    }

    private func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 15 }

    private var nodes: [FolderBrowserNode] {
        var result: [FolderBrowserNode] = []
        func append(_ url: URL, name: String, depth: Int) {
            result.append(FolderBrowserNode(url: url, name: name, depth: depth))
            guard browser.expanded.contains(url.path) else { return }
            for child in browser.children[url.path] ?? [] {
                append(child.url, name: child.name, depth: depth + 1)
            }
        }
        append(browser.rootURL, name: FileManager.default.displayName(atPath: browser.rootURL.path), depth: 0)
        return result
    }
}
