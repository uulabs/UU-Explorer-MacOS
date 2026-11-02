import AppKit
import Combine
import Darwin
import ExplorerCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PropertiesWindowController: NSWindowController, NSWindowDelegate {
    private static var windows: [URL: PropertiesWindowController] = [:]
    private let url: URL
    private let properties: PropertiesModel

    static func show(for url: URL) {
        let url = url.standardizedFileURL
        if let existing = windows[url] {
            existing.showWindow(nil)
            existing.window?.deminiaturize(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = PropertiesWindowController(url: url)
        windows[url] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(url: URL) {
        self.url = url
        let properties = PropertiesModel(url: url)
        self.properties = properties
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent) Properties"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PropertiesView(model: properties) {
            window.performClose(nil)
        })
        window.center()
        super.init(window: window)
        window.delegate = self
        properties.refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        properties.cancel()
        window?.contentView = nil
        Self.windows[url] = nil
    }
}

private struct MetadataRow: Identifiable {
    let id = UUID()
    let title: String
    let value: String
}

@MainActor
private final class PropertiesModel: ObservableObject {
    let url: URL
    @Published var statistics = FolderStatistics()
    @Published var created: Date?
    @Published var modified: Date?
    @Published var kind = "Folder"
    @Published var access = "—"
    @Published var volume: VolumeMetadata?
    @Published var permissions = "—"
    @Published var owner = "—"
    @Published var group = "—"
    @Published var hardLinkCount = 0
    @Published var typeIdentifier = "—"
    @Published var symlinkTarget: String?
    @Published var extendedAttributes: [String] = []
    @Published var acl: [String] = []
    @Published var imageMetadata: [MetadataRow] = []
    @Published var isQuarantined = false
    @Published var checksum: String?
    @Published var checksumState = ChecksumState.idle
    private var scan: Task<Void, Never>?
    private var checksumTask: Task<Void, Never>?

    enum ChecksumState {
        case idle
        case calculating
        case failed
    }

    init(url: URL) { self.url = url }

    private func loadMetadata() {
        let manager = FileManager.default
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        if let mode = attributes?[.posixPermissions] as? NSNumber {
            permissions = String(format: "%03o", mode.intValue)
        }
        owner = attributes?[.ownerAccountName] as? String ?? "—"
        group = attributes?[.groupOwnerAccountName] as? String ?? "—"
        hardLinkCount = Int(attributes?[.referenceCount] as? UInt ?? 0)

        var info = stat()
        if stat(url.path, &info) == 0 {
            hardLinkCount = Int(info.st_nlink)
        }

        let resourceValues = try? url.resourceValues(forKeys: [.typeIdentifierKey, .isSymbolicLinkKey])
        if let identifier = resourceValues?.typeIdentifier {
            typeIdentifier = UTType(identifier)?.localizedDescription ?? identifier
        }
        if resourceValues?.isSymbolicLink == true {
            symlinkTarget = try? manager.destinationOfSymbolicLink(atPath: url.path)
        }

        extendedAttributes = extendedAttributeNames()
        isQuarantined = extendedAttributes.contains("com.apple.quarantine")
        acl = accessControlEntries()
        imageMetadata = imageProperties()
    }

    private func extendedAttributeNames() -> [String] {
        let size = listxattr(url.path, nil, 0, 0)
        guard size > 0 else { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        let result = listxattr(url.path, &buffer, size, 0)
        guard result > 0 else { return [] }
        let data = Data(bytes: buffer, count: result)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\0")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func accessControlEntries() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ls")
        process.arguments = ["-led", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return [] }
        guard let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                guard let range = line.range(of: #"^\s*\d+:\s"#, options: .regularExpression) else { return false }
                return range.lowerBound == line.startIndex
            }
    }

    private func imageProperties() -> [MetadataRow] {
        guard let type = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
              UTType(type)?.conforms(to: .image) == true,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return []
        }
        var rows: [MetadataRow] = []
        if let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue,
           let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue {
            rows.append(MetadataRow(title: "Dimensions", value: "\(width) × \(height) px"))
        }
        if let dpi = (properties[kCGImagePropertyDPIWidth as String] as? NSNumber)?.intValue {
            rows.append(MetadataRow(title: "Resolution", value: "\(dpi) DPI"))
        }
        if let profile = properties[kCGImagePropertyProfileName as String] as? String {
            rows.append(MetadataRow(title: "Color profile", value: profile))
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            if let make = tiff[kCGImagePropertyTIFFMake as String] as? String {
                rows.append(MetadataRow(title: "Camera make", value: make))
            }
            if let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                rows.append(MetadataRow(title: "Camera model", value: model))
            }
        }
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let date = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            rows.append(MetadataRow(title: "Captured", value: date))
        }
        return rows
    }

    func calculateChecksum() {
        guard !isDirectory else { return }
        checksumTask?.cancel()
        checksumState = .calculating
        checksum = nil
        let url = url
        checksumTask = Task { [weak self] in
            let value = await Task.detached(priority: .utility) {
                FileHasher.sha256(at: url)
            }.value
            guard !Task.isCancelled else { return }
            self?.checksum = value
            self?.checksumState = value == nil ? .failed : .idle
        }
    }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    func refresh() {
        scan?.cancel()
        checksumTask?.cancel()
        statistics = FolderStatistics()
        volume = nil
        checksum = nil
        checksumState = .idle
        loadMetadata()

        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey,
                                                      .isDirectoryKey, .isSymbolicLinkKey])
        created = values?.creationDate
        modified = values?.contentModificationDate
        let manager = FileManager.default

        if let volume = VolumeMetadata.load(for: url) {
            self.volume = volume
            kind = volume.format
            access = volume.isReadOnly
                ? "Read only"
                : (manager.isWritableFile(atPath: url.path) ? "Read & write" : "Read only")
            return
        }

        kind = values?.isSymbolicLink == true ? "Symbolic link" : (values?.isDirectory == true ? "Folder" : "File")
        access = manager.isReadableFile(atPath: url.path)
            ? (manager.isWritableFile(atPath: url.path) ? "Read & write" : "Read only") : "No read access"
        let target = url
        scan = Task { [weak self] in
            let updates = AsyncStream<FolderStatistics> { continuation in
                let worker = Task.detached(priority: .utility) {
                    let result = FolderStatistics.calculate(at: target, isCancelled: { Task.isCancelled }) {
                        continuation.yield($0)
                    }
                    continuation.yield(result)
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in worker.cancel() }
            }
            for await update in updates {
                guard !Task.isCancelled else { break }
                self?.statistics = update
            }
        }
    }

    func cancel() {
        scan?.cancel()
        checksumTask?.cancel()
        if !statistics.isComplete { statistics.isCancelled = true }
    }
}

private struct PropertiesView: View {
    @ObservedObject var model: PropertiesModel
    let close: () -> Void

    private var totals: FolderStatistics { model.statistics }
    private var running: Bool { model.volume == nil && !totals.isComplete && !totals.isCancelled }
    private var partial: Bool { model.volume == nil && (totals.inaccessibleCount > 0 || totals.isCancelled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let volume = model.volume {
                        volumeBody(volume)
                    } else {
                        folderBody
                        metadataSection
                    }
                }
                .padding(.trailing, 4)
            }

            Divider()
            footer
        }
        .padding(24)
        .frame(width: 620, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: model.url.path))
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.url.lastPathComponent.isEmpty ? "/" : model.url.lastPathComponent)
                    .font(.system(size: 22, weight: .semibold)).lineLimit(2)
                Text(model.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(model.volume == nil ? "GENERAL" : "VOLUME")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
        }
    }

    private var folderBody: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Location").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(model.url.path).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                    .help(model.url.path)
            }
            HStack(spacing: 12) {
                sizeCard("Size", bytes: totals.logicalBytes)
                sizeCard("Size on disk", bytes: totals.allocatedBytes)
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 13) {
                detail("Contains", "\(totals.fileCount.formatted()) files, \(totals.folderCount.formatted()) folders")
                if totals.symbolicLinkCount > 0 {
                    detail("Symbolic links", totals.symbolicLinkCount.formatted())
                }
                detail("Created", date(model.created))
                detail("Modified", date(model.modified))
                detail("Access", model.access)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if running { ProgressView().controlSize(.small) }
                    else { Image(systemName: partial ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(partial ? Color.orange : Color.green) }
                    Text(running ? "Calculating folder contents…" : (partial ? "Partial totals" : "Calculation complete"))
                        .font(.system(size: 12, weight: .medium))
                }
                if totals.inaccessibleCount > 0 {
                    Text("\(totals.inaccessibleCount.formatted()) items could not be read. Totals exclude inaccessible contents.")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                if totals.isCancelled {
                    Text("Calculation stopped. Refresh to calculate again.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Includes hidden files and package contents. Symbolic links are counted without following their targets.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Size on disk reports allocated file blocks, counts hard links once, and excludes folder metadata. Shared APFS blocks may appear in more than one folder.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("METADATA")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 9) {
                detail("Permissions", model.permissions)
                detail("Owner", model.owner)
                detail("Group", model.group)
                detail("Hard links", "\(model.hardLinkCount)")
                detail("Type", model.typeIdentifier)
                detail("Quarantine", model.isQuarantined ? "Yes" : "No")
                if let target = model.symlinkTarget {
                    detail("Symlink target", target)
                }
            }

            if !model.extendedAttributes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extended attributes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.extendedAttributes.joined(separator: "\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(8)
                }
            }

            if !model.acl.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Access control")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(model.acl.joined(separator: "\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !model.imageMetadata.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Image")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                        ForEach(model.imageMetadata) { row in
                            GridRow(alignment: .top) {
                                Text(row.title).foregroundStyle(.secondary)
                                Text(row.value).textSelection(.enabled)
                            }
                            .font(.system(size: 11))
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Text("SHA-256")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if model.isDirectory {
                    Text("Available for files")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else if model.checksumState == .calculating {
                    ProgressView().controlSize(.small)
                    Text("Calculating…").font(.system(size: 10.5)).foregroundStyle(.secondary)
                } else {
                    Button(model.checksum == nil ? "Calculate" : "Recalculate") {
                        model.calculateChecksum()
                    }
                    .controlSize(.small)
                }
            }

            if let checksum = model.checksum {
                HStack(alignment: .top, spacing: 8) {
                    Text(checksum)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(checksum, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Copy SHA-256")
                }
            } else if model.checksumState == .failed {
                Text("Couldn’t calculate a checksum for this item.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func volumeBody(_ volume: VolumeMetadata) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                capacityCard("Used", bytes: volume.usedCapacity)
                capacityCard("Available", bytes: volume.availableCapacity)
                capacityCard("Total", bytes: volume.totalCapacity)
            }

            if let used = volume.usedCapacity,
               let total = volume.totalCapacity,
               total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(used), total: Double(total))
                        .tint(.accentColor)
                    HStack {
                        Text("\(Int((Double(used) / Double(total) * 100).rounded()))% used")
                        Spacer()
                        Text("Capacity reported by macOS")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 13) {
                detail("Format", volume.format)
                detail("Mount point", volume.mountPoint)
                if let uuid = volume.uuid {
                    detail("Volume UUID", uuid)
                }
                detail("Media", volume.mediaDescription)
                detail("Access", volume.isReadOnly ? "Read only" : model.access)
                detail("System volume", volume.isRootFileSystem ? "Yes" : "No")
                detail("Created", date(model.created))
                detail("Modified", date(model.modified))
            }

            Text("Used capacity is total capacity minus the capacity macOS reports as available. This is volume-level information, not a sum of files in the folder.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.url.path, forType: .string)
            }
            Spacer()
            if running { Button("Stop") { model.cancel() } }
            Button("Refresh") { model.refresh() }
            Button("Close", action: close).keyboardShortcut(.defaultAction)
        }
    }

    private func sizeCard(_ title: String, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.system(size: 25, weight: .semibold))
                .monospacedDigit().foregroundStyle(running || partial ? Color.secondary : Color.primary)
            Text(ByteFormat.exact(bytes)).font(.system(size: 10)).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func capacityCard(_ title: String, bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.system(size: 23, weight: .semibold))
                .monospacedDigit()
            Text(bytes.map(ByteFormat.exact) ?? "Unavailable")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }.font(.system(size: 12))
    }

    private func date(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .standard) ?? "—"
    }
}
