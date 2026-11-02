import ExplorerCore
import SwiftUI

struct FolderCompareView: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var differences: [FolderDifference] = []
    @State private var selection = Set<String>()
    @State private var showIdentical = false
    @State private var isLoading = true
    @State private var error: String?

    private var leftModel: ExplorerModel { session.primary.model }
    private var rightModel: ExplorerModel? { session.secondary?.model }
    private var visibleDifferences: [FolderDifference] {
        showIdentical ? differences : differences.filter(\.isDifference)
    }
    private var selectedDifferences: [FolderDifference] {
        differences.filter { selection.contains($0.id) }
    }
    private var differingCount: Int {
        differences.filter(\.isDifference).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare Folders")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(differingCount) difference\(differingCount == 1 ? "" : "s")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    load()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                paneHeader(title: "LEFT", path: leftModel.currentURL.path)
                Divider()
                paneHeader(title: "RIGHT", path: rightModel?.currentURL.path ?? "—")
            }
            .frame(height: 48)

            Divider()

            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Comparing folders…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Couldn’t compare folders").fontWeight(.semibold)
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selection) {
                    ForEach(visibleDifferences) { difference in
                        differenceRow(difference)
                            .tag(difference.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack(spacing: 8) {
                Toggle("Show identical items", isOn: $showIdentical)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10.5))
                Spacer()
                Button("Copy Left → Right") {
                    copySelectedFromLeft()
                }
                .disabled(isLoading || selectedDifferences.isEmpty)
                Button("Copy Right → Left") {
                    copySelectedFromRight()
                }
                .disabled(isLoading || selectedDifferences.isEmpty)
                Menu("Copy Changed") {
                    Button("Left → Right") { copyAllFromLeft() }
                    Button("Right → Left") { copyAllFromRight() }
                }
                .disabled(isLoading || differingCount == 0)
            }
            .padding(14)
        }
        .frame(width: 920, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { load() }
    }

    private func paneHeader(title: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(path)
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    private func differenceRow(_ difference: FolderDifference) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(for: difference.state))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color(for: difference.state))
                .frame(width: 18)
            Text(difference.name)
                .font(.system(size: 11.5, weight: difference.isDifference ? .medium : .regular))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail(difference.left))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)
                .lineLimit(1)
            Text(detail(difference.right))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }

    private func detail(_ item: FileItem?) -> String {
        guard let item else { return "—" }
        if item.isDirectory { return "Folder" }
        return ByteFormat.string(item.byteSize)
    }

    private func symbol(for state: FolderDifferenceState) -> String {
        switch state {
        case .leftOnly: return "arrow.right"
        case .rightOnly: return "arrow.left"
        case .different: return "exclamationmark.triangle.fill"
        case .identical: return "checkmark"
        }
    }

    private func color(for state: FolderDifferenceState) -> Color {
        switch state {
        case .leftOnly, .rightOnly: return .blue
        case .different: return .orange
        case .identical: return .secondary
        }
    }

    private func load() {
        guard let rightModel else {
            error = "Split View is no longer open."
            isLoading = false
            return
        }
        isLoading = true
        error = nil
        let leftURL = leftModel.currentURL
        let rightURL = rightModel.currentURL
        let leftHidden = leftModel.showHidden
        let rightHidden = rightModel.showHidden
        Task {
            do {
                async let leftItems = Task.detached(priority: .userInitiated) {
                    try FileSystemService.listDirectory(at: leftURL, includeHidden: leftHidden)
                }.value
                async let rightItems = Task.detached(priority: .userInitiated) {
                    try FileSystemService.listDirectory(at: rightURL, includeHidden: rightHidden)
                }.value
                let comparison = FolderComparator.compare(left: try await leftItems, right: try await rightItems)
                differences = comparison
                isLoading = false
                selection = selection.intersection(Set(comparison.map(\.id)))
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func copySelectedFromLeft() {
        let urls = selectedDifferences.compactMap { $0.left?.url }
        copy(urls, from: leftModel)
    }

    private func copySelectedFromRight() {
        guard let rightModel else { return }
        let urls = selectedDifferences.compactMap { $0.right?.url }
        copy(urls, from: rightModel)
    }

    private func copyAllFromLeft() {
        let urls = differences.filter(\.isDifference).compactMap { $0.left?.url }
        copy(urls, from: leftModel)
    }

    private func copyAllFromRight() {
        guard let rightModel else { return }
        let urls = differences.filter(\.isDifference).compactMap { $0.right?.url }
        copy(urls, from: rightModel)
    }

    private func copy(_ urls: [URL], from source: ExplorerModel) {
        guard let rightModel, !urls.isEmpty else { return }
        let isFromLeft = source === leftModel
        let destinationModel = isFromLeft ? rightModel : leftModel
        let destination = destinationModel.currentURL
        source.transfer(urls, to: destination, copy: true) { [weak destinationModel] in
            destinationModel?.reload()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                load()
            }
        }
    }
}
