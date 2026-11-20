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

private struct MetadataRow: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let value: String
}

private struct PropertiesSnapshot: Sendable {
    var created: Date?
    var modified: Date?
    var kind: String
    var access: String
    var volumeResult: VolumeMetadata.LoadResult
    var permissions: String
    var owner: String
    var group: String
    var hardLinkCount: Int
    var typeIdentifier: String
    var symlinkTarget: String?
    var extendedAttributes: [String]
    var acl: [String]
    var imageMetadata: [MetadataRow]
    var isDirectory: Bool
}

private struct IconBox: @unchecked Sendable {
    let image: NSImage
}

@MainActor
private final class PropertiesModel: ObservableObject {
    let url: URL
    @Published var statistics = FolderStatistics()
    @Published var created: Date?
    @Published var modified: Date?
    @Published var kind = "Loading…"
    @Published var access = "—"
    @Published var volume: VolumeMetadata?
    @Published var volumeMetadataUnavailable = false
    @Published var isKnownVolumeRoot = false
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
    @Published var isDirectory = false
    @Published var isMetadataLoaded = false
    @Published var icon: NSImage?
    @Published var checksum: String?
    @Published var checksumState = ChecksumState.idle
    @Published var isCalculating = false
    @Published var calculationTaskActive = false
    private var loadTask: Task<Void, Never>?
    private var iconTask: Task<Void, Never>?
    private var scan: Task<Void, Never>?
    private var checksumTask: Task<Void, Never>?
    private var generation = 0
    private var scanGeneration = 0

    enum ChecksumState {
        case idle
        case calculating
        case failed
    }

    init(url: URL) { self.url = url }

    var canCalculate: Bool {
        isMetadataLoaded && !isKnownVolumeRoot && !calculationTaskActive
    }

    nonisolated private static func snapshot(for url: URL) -> PropertiesSnapshot {
        let manager = FileManager.default
        let attributes = try? manager.attributesOfItem(atPath: url.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber).map {
            String(format: "%03o", $0.intValue)
        } ?? "—"
        let owner = attributes?[.ownerAccountName] as? String ?? "—"
        let group = attributes?[.groupOwnerAccountName] as? String ?? "—"
        var hardLinkCount = (attributes?[.referenceCount] as? NSNumber)?.intValue ?? 0

        var info = stat()
        if stat(url.path, &info) == 0 {
            hardLinkCount = Int(info.st_nlink)
        }

        let values = try? url.resourceValues(forKeys: [
            .creationDateKey,
            .contentModificationDateKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .typeIdentifierKey
        ])
        let typeIdentifier = values?.typeIdentifier.map {
            UTType($0)?.localizedDescription ?? $0
        } ?? "—"
        let symlinkTarget = values?.isSymbolicLink == true
            ? try? manager.destinationOfSymbolicLink(atPath: url.path)
            : nil
        let extendedAttributes = extendedAttributeNames(for: url)
        let volumeResult = VolumeMetadata.resolve(for: url)
        let kind: String
        let access: String
        switch volumeResult {
        case .loaded(let volume):
            kind = volume.format
            access = volume.isReadOnly
                ? "Read only"
                : (manager.isWritableFile(atPath: url.path) ? "Read & write" : "Read only")
        case .unavailable:
            kind = "Volume"
            access = "Unavailable"
        case .notVolumeRoot:
            kind = values?.isSymbolicLink == true
                ? "Symbolic link"
                : (values?.isDirectory == true ? "Folder" : "File")
            access = manager.isReadableFile(atPath: url.path)
                ? (manager.isWritableFile(atPath: url.path) ? "Read & write" : "Read only")
                : "No read access"
        }

        return PropertiesSnapshot(
            created: values?.creationDate,
            modified: values?.contentModificationDate,
            kind: kind,
            access: access,
            volumeResult: volumeResult,
            permissions: permissions,
            owner: owner,
            group: group,
            hardLinkCount: hardLinkCount,
            typeIdentifier: typeIdentifier,
            symlinkTarget: symlinkTarget,
            extendedAttributes: extendedAttributes,
            acl: accessControlEntries(for: url),
            imageMetadata: imageProperties(for: url),
            isDirectory: values?.isDirectory == true
        )
    }

    nonisolated private static func extendedAttributeNames(for url: URL) -> [String] {
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

    nonisolated private static func accessControlEntries(for url: URL) -> [String] {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else { return [] }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard let text = acl_to_text(acl, nil) else { return [] }
        defer { acl_free(text) }
        return String(cString: text).split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                guard let range = line.range(of: #"^\s*\d+:\s"#, options: .regularExpression) else { return false }
                return range.lowerBound == line.startIndex
            }
    }

    nonisolated private static func imageProperties(for url: URL) -> [MetadataRow] {
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

    private func apply(_ snapshot: PropertiesSnapshot) {
        created = snapshot.created
        modified = snapshot.modified
        kind = snapshot.kind
        access = snapshot.access
        permissions = snapshot.permissions
        owner = snapshot.owner
        group = snapshot.group
        hardLinkCount = snapshot.hardLinkCount
        typeIdentifier = snapshot.typeIdentifier
        symlinkTarget = snapshot.symlinkTarget
        extendedAttributes = snapshot.extendedAttributes
        isQuarantined = snapshot.extendedAttributes.contains("com.apple.quarantine")
        acl = snapshot.acl
        imageMetadata = snapshot.imageMetadata
        isDirectory = snapshot.isDirectory
        switch snapshot.volumeResult {
        case .loaded(let metadata):
            volume = metadata
            isKnownVolumeRoot = true
        case .unavailable:
            volumeMetadataUnavailable = true
            isKnownVolumeRoot = true
        case .notVolumeRoot:
            break
        }
        isMetadataLoaded = true
    }

    func calculateChecksum() {
        guard isMetadataLoaded, !isDirectory, !isKnownVolumeRoot else { return }
        checksumTask?.cancel()
        checksumState = .calculating
        checksum = nil
        let url = url
        let request = generation
        checksumTask = Task { [weak self] in
            let value = await Task.detached(priority: .utility) {
                FileHasher.sha256(at: url)
            }.value
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.checksum = value
            self.checksumState = value == nil ? .failed : .idle
        }
    }

    func calculateTotals() {
        guard canCalculate else { return }
        scanGeneration += 1
        let request = scanGeneration
        let target = url
        statistics = FolderStatistics()
        isCalculating = true
        calculationTaskActive = true
        scan = Task { [weak self] in
            let updates = AsyncStream<FolderStatistics>(bufferingPolicy: .bufferingNewest(1)) { continuation in
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
                guard let self, self.scanGeneration == request else { break }
                self.statistics = update
            }
            guard let self else { return }
            self.scan = nil
            self.calculationTaskActive = false
            if self.scanGeneration == request {
                self.isCalculating = false
            }
        }
    }

    func stopCalculation() {
        guard scan != nil else { return }
        scanGeneration += 1
        scan?.cancel()
        isCalculating = false
        if !statistics.isComplete { statistics.isCancelled = true }
    }

    func refresh() {
        generation += 1
        scanGeneration += 1
        let request = generation
        loadTask?.cancel()
        iconTask?.cancel()
        scan?.cancel()
        checksumTask?.cancel()
        statistics = FolderStatistics()
        isCalculating = false
        calculationTaskActive = scan != nil
        volume = nil
        volumeMetadataUnavailable = false
        isKnownVolumeRoot = false
        isMetadataLoaded = false
        created = nil
        modified = nil
        kind = "Loading…"
        access = "—"
        permissions = "—"
        owner = "—"
        group = "—"
        hardLinkCount = 0
        typeIdentifier = "—"
        symlinkTarget = nil
        extendedAttributes = []
        acl = []
        imageMetadata = []
        isQuarantined = false
        isDirectory = false
        icon = nil
        checksum = nil
        checksumState = .idle

        let target = url
        loadTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.snapshot(for: target)
            }.value
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.apply(snapshot)
        }
        iconTask = Task { [weak self] in
            let box = await Task.detached(priority: .userInitiated) {
                IconBox(image: NSWorkspace.shared.icon(forFile: target.path))
            }.value
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.icon = box.image
        }
    }

    func cancel() {
        generation += 1
        loadTask?.cancel()
        iconTask?.cancel()
        checksumTask?.cancel()
        stopCalculation()
    }
}

private struct PropertiesView: View {
    @ObservedObject var model: PropertiesModel
    let close: () -> Void

    private var totals: FolderStatistics { model.statistics }
    private var running: Bool { model.isCalculating }
    private var hasCalculation: Bool { running || totals.isComplete || totals.isCancelled }
    private var partial: Bool { hasCalculation && (totals.inaccessibleCount > 0 || totals.isCancelled) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let volume = model.volume {
                        volumeBody(volume)
                    } else if model.volumeMetadataUnavailable {
                        volumeUnavailableBody
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
            Group {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "doc").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.url.lastPathComponent.isEmpty ? "/" : model.url.lastPathComponent)
                    .font(.system(size: 22, weight: .semibold)).lineLimit(2)
                Text(model.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(model.isKnownVolumeRoot ? "VOLUME" : "GENERAL")
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
                sizeCard("Size", bytes: hasCalculation ? totals.logicalBytes : nil)
                sizeCard("Size on disk", bytes: hasCalculation ? totals.allocatedBytes : nil)
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 13) {
                detail("Contains", hasCalculation
                    ? "\(totals.fileCount.formatted()) files, \(totals.folderCount.formatted()) folders"
                    : "Not calculated")
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
                    if running {
                        ProgressView().controlSize(.small)
                        Text("Calculating folder contents…")
                    } else if hasCalculation {
                        Image(systemName: partial ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(partial ? Color.orange : Color.green)
                        Text(partial ? "Partial totals" : "Calculation complete")
                    } else {
                        Text("Folder totals are calculated only on request.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !running {
                        Button(totals.isComplete ? "Recalculate" : "Calculate") {
                            model.calculateTotals()
                        }
                        .controlSize(.small)
                        .disabled(!model.canCalculate)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                if totals.inaccessibleCount > 0 {
                    Text("\(totals.inaccessibleCount.formatted()) items could not be read. Totals exclude inaccessible contents.")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                if totals.isCancelled {
                    Text("Calculation stopped. The displayed totals are partial.")
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
                detail("Hard links", model.isMetadataLoaded ? "\(model.hardLinkCount)" : "—")
                detail("Type", model.typeIdentifier)
                detail("Quarantine", model.isMetadataLoaded ? (model.isQuarantined ? "Yes" : "No") : "—")
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
                    .disabled(!model.isMetadataLoaded)
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

    private var volumeUnavailableBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Volume information unavailable", systemImage: "exclamationmark.triangle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
            Text("macOS could not provide metadata for this volume root. Recursive totals are not calculated when volume metadata cannot be read.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 13) {
                detail("Mount point", model.url.path)
                detail("Access", model.access)
                detail("Created", date(model.created))
                detail("Modified", date(model.modified))
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
            if running { Button("Stop") { model.stopCalculation() } }
            Button("Refresh") { model.refresh() }
            Button("Close", action: close).keyboardShortcut(.defaultAction)
        }
    }

    private func sizeCard(_ title: String, bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.system(size: 25, weight: .semibold))
                .monospacedDigit().foregroundStyle(running || partial ? Color.secondary : Color.primary)
            Text(bytes.map(ByteFormat.exact) ?? "Not calculated").font(.system(size: 10)).foregroundStyle(.secondary)
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
