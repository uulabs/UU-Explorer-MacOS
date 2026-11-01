import AppKit
import ExplorerCore
import SwiftUI

struct ArchiveBrowserRequest: Identifiable {
    let id = UUID()
    let archive: URL
}

@MainActor
private final class ArchiveBrowserModel: ObservableObject {
    let archive: URL
    @Published private(set) var entries: [ArchiveEntry] = []
    @Published var selection = Set<String>()
    @Published var query = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isWorking = false
    @Published var error: String?
    @Published var status: String?

    init(archive: URL) {
        self.archive = archive
    }

    var filteredEntries: [ArchiveEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.path.localizedCaseInsensitiveContains(trimmed) }
    }

    var selectedEntries: [ArchiveEntry] {
        entries.filter { selection.contains($0.id) }
    }

    func load() {
        isLoading = true
        error = nil
        let archive = archive
        Task { [weak self] in
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try ArchiveService.entries(of: archive)
                }.value
                guard let self else { return }
                self.entries = entries
                self.isLoading = false
            } catch {
                guard let self else { return }
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func openSelection() {
        let files = selectedEntries.filter { !$0.isDirectory }
        guard !files.isEmpty, files.count == selectedEntries.count else {
            error = "Select files to open."
            return
        }
        isWorking = true
        error = nil
        status = "Preparing files…"
        let archive = archive
        Task { [weak self] in
            do {
                let root = try Self.cacheDirectory()
                let urls = try await Task.detached(priority: .userInitiated) {
                    for entry in files {
                        try ArchiveService.extractEntry(entry, from: archive, to: root)
                    }
                    return files.map { root.appendingPathComponent($0.path) }
                }.value
                guard let self else { return }
                self.isWorking = false
                self.status = nil
                urls.forEach { NSWorkspace.shared.open($0) }
            } catch {
                self?.isWorking = false
                self?.status = nil
                self?.error = error.localizedDescription
            }
        }
    }

    func extractSelection() {
        let files = selectedEntries.filter { !$0.isDirectory }
        guard !files.isEmpty, files.count == selectedEntries.count else {
            error = "Select files to extract."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Extract Selected Items"
        panel.message = "Choose a destination folder."
        panel.prompt = "Extract"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url?.standardizedFileURL else { return }

        isWorking = true
        error = nil
        status = "Extracting \(files.count) item\(files.count == 1 ? "" : "s")…"
        let archive = archive
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    for entry in files {
                        try ArchiveService.extractEntry(entry, from: archive, to: destination)
                    }
                }.value
                guard let self else { return }
                self.isWorking = false
                self.status = "Extracted to \(destination.path)"
            } catch {
                self?.isWorking = false
                self?.status = nil
                self?.error = error.localizedDescription
            }
        }
    }

    private static func cacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = caches
            .appendingPathComponent("UU Explorer", isDirectory: true)
            .appendingPathComponent("Archive Browser", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

struct ArchiveBrowserView: View {
    @StateObject private var model: ArchiveBrowserModel
    @Environment(\.dismiss) private var dismiss

    init(archive: URL) {
        _model = StateObject(wrappedValue: ArchiveBrowserModel(archive: archive))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.archive.lastPathComponent)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(model.entries.isEmpty ? "Archive contents" : "\(model.entries.count) entries")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter archive contents", text: $model.query)
                    .textFieldStyle(.plain)
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 38)

            Divider()

            if model.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Reading archive…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.error, model.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Couldn’t read this archive")
                        .fontWeight(.semibold)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $model.selection) {
                    ForEach(model.filteredEntries) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .font(.system(size: 12))
                                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                                .frame(width: 16)
                            Text(entry.path)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if entry.isDirectory {
                                Text("Folder")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(entry.id)
                        .onTapGesture(count: 2) {
                            guard !entry.isDirectory else { return }
                            model.selection = [entry.id]
                            model.openSelection()
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack(spacing: 8) {
                if let status = model.status {
                    Text(status)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let error = model.error {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                Spacer()
                Button("Open") { model.openSelection() }
                    .disabled(model.isWorking || model.selectedEntries.isEmpty)
                Button("Extract Selected…") { model.extractSelection() }
                    .disabled(model.isWorking || model.selectedEntries.isEmpty)
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 760, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.load() }
    }
}
