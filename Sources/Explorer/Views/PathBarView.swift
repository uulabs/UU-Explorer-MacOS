import ExplorerCore
import SwiftUI

struct PathBarView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    @FocusState private var isFocused: Bool
    @State private var suggestions: [PathSuggestion] = []
    @State private var highlightedIndex: Int?
    @State private var completionTask: Task<Void, Never>?

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if model.isEditingPath {
                    editor
                } else {
                    breadcrumbs
                }
            }
            Rectangle().fill(theme.toolbarDivider)
                .frame(width: 1, height: 16)
            PathFolderDropdown(model: model, rootURL: model.currentURL)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(pathBackground)
        .overlay(alignment: .topLeading) {
            if model.isEditingPath, !suggestions.isEmpty {
                suggestionList
                    .offset(y: 34)
            }
        }
        .task(id: model.isEditingPath) {
            if model.isEditingPath {
                try? await Task.sleep(nanoseconds: 40_000_000)
                isFocused = true
                scheduleSuggestions()
            } else {
                isFocused = false
                suggestions = []
                highlightedIndex = nil
            }
        }
        .onChange(of: model.pathDraft) { _, _ in
            scheduleSuggestions()
        }
    }

    private var pathBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(theme.field)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }

    private var borderColor: Color {
        if model.isEditingPath && model.pathError {
            return Color.red.opacity(0.85)
        }
        if model.isEditingPath && isFocused {
            return theme.accent.opacity(0.9)
        }
        return theme.toolbarDivider
    }

    private var breadcrumbs: some View {
        let crumbs = displayCrumbs()
        return HStack(spacing: 1) {
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if let path = crumb.path {
                    PathSegmentButton(
                        name: crumb.name,
                        path: path,
                        isFirst: crumb.isFirst,
                        isCurrent: path == model.currentURL.path,
                        isInternalVolume: model.volume?.isInternal ?? true
                    ) {
                        model.navigate(to: URL(fileURLWithPath: path))
                    }
                } else {
                    Button {
                        model.beginPathEditing()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.toolbarSecondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Show full path")
                }

                if index < crumbs.count - 1, let path = crumb.path {
                    PathFolderDropdown(model: model, rootURL: URL(fileURLWithPath: path),
                                       symbol: "chevron.compact.right", compact: true)
                }
            }

            Button {
                model.beginPathEditing()
            } label: {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to edit the path (⌘L)")

            Button {
                model.beginPathEditing()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.toolbarSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit path (⌘L)")
        }
        .padding(.leading, 5)
        .padding(.trailing, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        HStack(spacing: 5) {
            Image(systemName: model.pathError ? "exclamationmark.triangle.fill" : "folder")
                .font(.system(size: 11))
                .foregroundStyle(model.pathError ? Color.red : theme.toolbarSecondary)

            TextField("Path", text: Binding(
                get: { model.pathDraft },
                set: { model.updatePathDraft($0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .foregroundStyle(theme.toolbarText)
            .focused($isFocused)
            .onSubmit { commit() }
            .onKeyPress(.escape) {
                model.cancelPathEditing()
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                moveHighlight(-1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                guard !suggestions.isEmpty else { return .ignored }
                moveHighlight(1)
                return .handled
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.75)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 26)
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    choose(suggestion)
                } label: {
                    HStack(spacing: 6) {
                        if suggestion.kind == .parent {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.accent)
                                .frame(width: 16, height: 16)
                                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        } else if suggestion.isDirectory {
                            Image(nsImage: theme.folderIcon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.toolbarSecondary)
                                .frame(width: 14)
                        }

                        Text(suggestion.name)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.toolbarText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(suggestion.kind == .parent ? "Parent" : (suggestion.isDirectory ? "Folder" : "File"))
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.toolbarSecondary)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightedIndex == index ? theme.accent.opacity(0.16) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help(suggestion.url.path)

                if suggestion.kind == .parent,
                   index + 1 < suggestions.count,
                   suggestions[index + 1].kind != .parent {
                    Rectangle()
                        .fill(theme.toolbarDivider)
                        .frame(height: 1)
                        .padding(.vertical, 3)
                }
            }
        }
        .padding(4)
        .frame(width: 380)
        .background(theme.toolbar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(theme.toolbarDivider, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 6)
    }

    private func displayCrumbs() -> [CrumbDisplay] {
        let crumbs = PathTools.breadcrumbs(
            for: model.currentURL,
            volumeRoot: model.breadcrumbVolumeRoot,
            volumeName: model.breadcrumbVolumeName
        )
        guard !crumbs.isEmpty else { return [] }

        if crumbs.count <= 6 {
            return crumbs.enumerated().map { index, crumb in
                CrumbDisplay(
                    id: crumb.path,
                    name: crumb.name,
                    path: crumb.path,
                    isFirst: index == 0
                )
            }
        }

        var result: [CrumbDisplay] = [
            CrumbDisplay(id: crumbs[0].path, name: crumbs[0].name, path: crumbs[0].path, isFirst: true),
            CrumbDisplay(id: "ellipsis", name: "…", path: nil, isFirst: false)
        ]
        for crumb in crumbs.suffix(4) {
            result.append(
                CrumbDisplay(id: crumb.path, name: crumb.name, path: crumb.path, isFirst: false)
            )
        }
        return result
    }

    private func scheduleSuggestions() {
        completionTask?.cancel()
        let draft = model.pathDraft
        guard model.isEditingPath, !draft.isEmpty else {
            suggestions = []
            highlightedIndex = nil
            return
        }

        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            let base = model.currentURL
            let home = model.home
            let results = await Task.detached(priority: .userInitiated) {
                PathCompleter.suggestions(for: draft, base: base, home: home)
            }.value

            guard !Task.isCancelled, model.pathDraft == draft else { return }
            suggestions = results
            highlightedIndex = nil
        }
    }

    private func moveHighlight(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        if let current = highlightedIndex {
            highlightedIndex = min(max(current + delta, 0), suggestions.count - 1)
        } else {
            highlightedIndex = delta > 0 ? 0 : suggestions.count - 1
        }
    }

    private func choose(_ suggestion: PathSuggestion) {
        model.pathDraft = suggestion.url.path
        model.commitPath()
        suggestions = []
        highlightedIndex = nil
    }

    private func commit() {
        if let index = highlightedIndex, suggestions.indices.contains(index) {
            model.pathDraft = suggestions[index].url.path
        }
        if model.commitPath() {
            suggestions = []
            highlightedIndex = nil
            isFocused = false
        }
    }
}

private struct CrumbDisplay: Identifiable {
    let id: String
    let name: String
    let path: String?
    let isFirst: Bool
}

private struct PathSegmentButton: View {
    let name: String
    let path: String
    let isFirst: Bool
    let isCurrent: Bool
    let isInternalVolume: Bool
    let action: () -> Void
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var isHovering = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if isFirst {
                    Image(systemName: isInternalVolume ? "internaldrive" : "externaldrive")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.toolbarSecondary)
                }
                Text(name)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(theme.toolbarText.opacity(isCurrent ? 1 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 5)
            .frame(height: 21)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? theme.toolbarText.opacity(0.065) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(path)
    }
}
