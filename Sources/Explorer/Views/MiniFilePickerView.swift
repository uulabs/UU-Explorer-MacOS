import ExplorerCore
import SwiftUI

@MainActor
private final class MiniFilePickerModel: ObservableObject {
    @Published var path: URL
    @Published var entries: [MiniFileEntry] = []
    @Published var selected: Set<URL> = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showHidden = false

    init(initialDirectory: URL) {
        let stored = UserDefaults.standard.string(forKey: "UUExplorer.androidPushDirectory")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let candidate = stored.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? initialDirectory
        let directory = FileManager.default.fileExists(atPath: candidate.path)
            ? candidate
            : FileManager.default.homeDirectoryForCurrentUser
        self.path = directory
    }

    func load() {
        let requested = path
        let includeHidden = showHidden
        isLoading = true
        error = nil
        Task {
            do {
                let entries = try await Task.detached(priority: .userInitiated) {
                    try Self.readDirectory(requested, includeHidden: includeHidden)
                }.value
                guard requested == path else { return }
                self.entries = entries
                self.selected = self.selected.filter { url in
                    entries.contains { $0.url == url && !$0.isDirectory }
                }
                self.isLoading = false
            } catch {
                self.entries = []
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func navigate(to entry: MiniFileEntry) {
        guard entry.isDirectory else { return }
        path = entry.url
        selected = []
        load()
    }

    func up() {
        guard path.path != "/" else { return }
        path = path.deletingLastPathComponent()
        selected = []
        load()
    }

    func go(to url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        path = url
        selected = []
        load()
    }

    func toggle(_ entry: MiniFileEntry) {
        guard !entry.isDirectory else {
            navigate(to: entry)
            return
        }
        if selected.contains(entry.url) {
            selected.remove(entry.url)
        } else {
            selected.insert(entry.url)
        }
    }

    func selectAllFiles() {
        selected = Set(entries.filter { !$0.isDirectory }.map(\.url))
    }

    func rememberDirectory() {
        UserDefaults.standard.set(path.path, forKey: "UUExplorer.androidPushDirectory")
    }

    nonisolated private static func readDirectory(_ directory: URL, includeHidden: Bool) throws -> [MiniFileEntry] {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey
        ]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        )
        let entries = urls.compactMap { url -> MiniFileEntry? in
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { return nil }
            return MiniFileEntry(
                url: url,
                isDirectory: values.isDirectory == true,
                isSymbolicLink: values.isSymbolicLink == true,
                size: values.fileSize.map(Int64.init),
                modified: values.contentModificationDate
            )
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}

private struct MiniFileEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let size: Int64?
    let modified: Date?

    var id: URL { url }
}

private struct MiniFileRow: View {
    let entry: MiniFileEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if entry.isDirectory {
                Color.clear.frame(width: 15, height: 15)
            } else {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 15)
            }
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                .frame(width: 17)
            Text(entry.url.lastPathComponent)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(entry.modified?.formatted(date: .abbreviated, time: .shortened) ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            Text(entry.isDirectory ? "—" : entry.size.map(ByteFormat.string) ?? "")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private var symbol: String {
        if entry.isDirectory { return "folder" }
        switch entry.url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg": return "photo"
        case "mp4", "mov", "m4v", "webm": return "film"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox"
        case "apk": return "shippingbox"
        case "swift", "js", "ts", "py", "sh", "json", "html", "css": return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}

struct MiniFilePickerView: View {
    @StateObject private var model: MiniFilePickerModel
    @Environment(\.dismiss) private var dismiss
    let destination: String
    let onChoose: ([URL]) -> Void

    init(initialDirectory: URL, destination: String, onChoose: @escaping ([URL]) -> Void) {
        _model = StateObject(wrappedValue: MiniFilePickerModel(initialDirectory: initialDirectory))
        self.destination = destination
        self.onChoose = onChoose
    }

    private var quickLinks: [(String, String, URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("Home", "house", home),
            ("Desktop", "menubar.dock.rectangle", home.appendingPathComponent("Desktop")),
            ("Documents", "doc", home.appendingPathComponent("Documents")),
            ("Downloads", "arrow.down.circle", home.appendingPathComponent("Downloads")),
            ("Applications", "square.grid.2x2", URL(fileURLWithPath: "/Applications")),
            ("Pictures", "photo", home.appendingPathComponent("Pictures")),
            ("Movies", "film", home.appendingPathComponent("Movies"))
        ].filter { FileManager.default.fileExists(atPath: $0.2.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "candybarphone")
                    .font(.system(size: 20))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Choose files to push")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Destination: \(destination)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MAC")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.top, 8)
                        .padding(.bottom, 3)
                    ForEach(quickLinks, id: \.0) { item in
                        Button {
                            model.go(to: item.2)
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: item.1)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tint)
                                    .frame(width: 16)
                                Text(item.0)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 155)
                .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))

                Divider()

                VStack(spacing: 0) {
                    HStack(spacing: 7) {
                        Button { model.up() } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(model.path.path == "/")
                        .help("Parent folder")
                        Text(model.path.path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Toggle("Hidden", isOn: $model.showHidden)
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .onChange(of: model.showHidden) { _, _ in model.load() }
                        Button { model.load() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh")
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 38)

                    Divider()

                    HStack(spacing: 8) {
                        Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                        Text("MODIFIED").frame(width: 130, alignment: .trailing)
                        Text("SIZE").frame(width: 72, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 24)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                    if model.isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Reading \(model.path.lastPathComponent)…")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = model.error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    } else if model.entries.isEmpty {
                        Text("This folder is empty.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(model.entries) { entry in
                                    MiniFileRow(entry: entry, isSelected: model.selected.contains(entry.url))
                                        .onTapGesture { model.toggle(entry) }
                                }
                            }
                            .padding(6)
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Text("\(model.selected.count) selected")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Button("Select All Files") { model.selectAllFiles() }
                            .controlSize(.small)
                        Spacer()
                        Button("Push \(model.selected.count) File\(model.selected.count == 1 ? "" : "s")") {
                            let urls = Array(model.selected)
                            model.rememberDirectory()
                            onChoose(urls)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selected.isEmpty)
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 760, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.load() }
    }
}
