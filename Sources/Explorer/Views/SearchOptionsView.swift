import ExplorerCore
import SwiftUI

struct SearchOptionsView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    private var sizeChoices: [(String, Int64?)] {
        [
            ("Any size", nil),
            ("10 MB+", 10 * 1_024 * 1_024),
            ("100 MB+", 100 * 1_024 * 1_024),
            ("1 GB+", 1_024 * 1_024 * 1_024),
            ("10 GB+", 10 * 1_024 * 1_024 * 1_024)
        ]
    }

    private var modifiedChoices: [(String, Int?)] {
        [("Any time", nil), ("Last 7 days", 7), ("Last 30 days", 30), ("Last year", 365)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Search Options", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Clear") { model.clearSearch() }
                    .font(.system(size: 10.5))
                    .disabled(!model.hasSearchCriteria)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Look for")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(theme.contentSecondary)
                Picker("Look for", selection: Binding(
                    get: { model.searchFilter.textMode },
                    set: { mode in
                        var filter = model.searchFilter
                        filter.textMode = mode
                        model.setSearchFilter(filter)
                    }
                )) {
                    ForEach(SearchTextMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack(spacing: 10) {
                searchMenu(
                    title: "Minimum size",
                    value: sizeLabel,
                    options: sizeChoices.map { ($0.0, $0.1) },
                    isSelected: { $0 == model.searchFilter.minimumSize },
                    select: { value in
                        var filter = model.searchFilter
                        filter.minimumSize = value
                        model.setSearchFilter(filter)
                    }
                )

                searchMenu(
                    title: "Type",
                    value: model.searchFilter.kind?.title ?? "Any type",
                    options: [("Any type", SearchKind?.none)] + SearchKind.allCases.map { ($0.title, Optional($0)) },
                    isSelected: { $0 == model.searchFilter.kind },
                    select: { value in
                        var filter = model.searchFilter
                        filter.kind = value
                        model.setSearchFilter(filter)
                    }
                )
            }

            HStack(spacing: 10) {
                searchMenu(
                    title: "Modified",
                    value: modifiedLabel,
                    options: modifiedChoices.map { ($0.0, $0.1) },
                    isSelected: { $0 == model.searchFilter.modifiedWithinDays },
                    select: { value in
                        var filter = model.searchFilter
                        filter.modifiedWithinDays = value
                        model.setSearchFilter(filter)
                    }
                )

                Picker("Scope", selection: Binding(
                    get: { model.searchScope },
                    set: { model.setSearchScope($0) }
                )) {
                    Text("This Folder").tag(SearchScope.folder)
                        .disabled(model.searchFilter.textMode != .name)
                    Text("Subfolders").tag(SearchScope.recursive)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if model.searchFilter.textMode != .name {
                Label("Contents search uses the Spotlight index and searches subfolders.", systemImage: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.contentSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Find Large Files") {
                    model.findLargeFiles()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Reset Filters") {
                    var filter = SearchFilter()
                    if model.filterText.isEmpty { filter.textMode = .name }
                    model.setSearchFilter(filter)
                    model.setFilter("")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.contentSecondary)
            }

            Text("Large-file searches work on unindexed volumes because they walk the folder tree directly.")
                .font(.system(size: 9.5))
                .foregroundStyle(theme.contentSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(width: 380)
        .background(theme.content)
    }

    private var sizeLabel: String {
        sizeChoices.first { $0.1 == model.searchFilter.minimumSize }?.0 ?? "Any size"
    }

    private var modifiedLabel: String {
        modifiedChoices.first { $0.1 == model.searchFilter.modifiedWithinDays }?.0 ?? "Any time"
    }

    @ViewBuilder
    private func searchMenu<Value: Equatable>(
        title: String,
        value: String,
        options: [(String, Value)],
        isSelected: @escaping (Value) -> Bool,
        select: @escaping (Value) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(theme.contentSecondary)
            Menu {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        select(option.1)
                    } label: {
                        if isSelected(option.1) {
                            Label(option.0, systemImage: "checkmark")
                        } else {
                            Text(option.0)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(value)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 11))
                .foregroundStyle(theme.contentText)
                .padding(.horizontal, 8)
                .frame(height: 25)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.field, in: RoundedRectangle(cornerRadius: 5))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .frame(maxWidth: .infinity)
    }
}
