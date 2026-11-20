import AppKit
import Combine
import ExplorerCore
import SwiftUI

@MainActor
final class SelectionPropertiesWindowController: NSWindowController, NSWindowDelegate {
    private static var windowController: SelectionPropertiesWindowController?
    private let properties: SelectionPropertiesModel

    static func show(for urls: [URL]) {
        var seen = Set<String>()
        let targets = urls.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
        guard !targets.isEmpty else { return }
        windowController?.window?.close()

        let controller = SelectionPropertiesWindowController(urls: targets)
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(urls: [URL]) {
        let properties = SelectionPropertiesModel(urls: urls)
        self.properties = properties
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(urls.count) Items Properties"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SelectionPropertiesView(model: properties) {
            window.performClose(nil)
        })
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        properties.cancel()
        window?.contentView = nil
        Self.windowController = nil
    }
}

@MainActor
final class SelectionPropertiesModel: ObservableObject {
    let urls: [URL]
    @Published var statistics = FolderStatistics()
    @Published var isCalculating = false
    @Published var calculationTaskActive = false
    @Published var completedRoots = 0
    @Published var currentItem: String?

    private var scan: Task<Void, Never>?
    private var generation = 0

    init(urls: [URL]) {
        self.urls = urls
    }

    var canCalculate: Bool { !calculationTaskActive }

    func calculateTotals() {
        guard canCalculate else { return }
        generation += 1
        let request = generation
        statistics = FolderStatistics()
        completedRoots = 0
        currentItem = nil
        isCalculating = true
        calculationTaskActive = true

        let targets = urls
        scan = Task { [weak self] in
            var completed = FolderStatistics()
            for (index, url) in targets.enumerated() {
                if Task.isCancelled { break }
                guard let self, self.generation == request else { return }
                self.currentItem = url.path

                let updates = AsyncStream<FolderStatistics>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                    let worker = Task.detached(priority: .utility) {
                        let result = FolderStatistics.calculate(at: url, isCancelled: { Task.isCancelled }) {
                            continuation.yield($0)
                        }
                        continuation.yield(result)
                        continuation.finish()
                    }
                    continuation.onTermination = { @Sendable _ in worker.cancel() }
                }

                var final = FolderStatistics()
                for await update in updates {
                    if Task.isCancelled { break }
                    final = update
                    self.publish(completed: completed, current: update)
                }
                completed = Self.combine(completed, final)
                self.completedRoots = index + 1
                self.publish(completed: completed, current: nil)
            }

            guard let self else { return }
            self.scan = nil
            self.calculationTaskActive = false
            if self.generation == request {
                if !Task.isCancelled, self.completedRoots == self.urls.count {
                    self.statistics.isComplete = true
                    self.statistics.isCancelled = false
                } else {
                    self.statistics.isComplete = false
                    self.statistics.isCancelled = true
                }
                self.isCalculating = false
                self.currentItem = nil
            }
        }
    }

    func stopCalculation() {
        guard scan != nil else { return }
        generation += 1
        scan?.cancel()
        isCalculating = false
        currentItem = nil
        statistics.isComplete = false
        statistics.isCancelled = true
    }

    func cancel() {
        stopCalculation()
    }

    private func publish(completed: FolderStatistics, current: FolderStatistics?) {
        statistics = Self.combine(completed, current ?? FolderStatistics())
    }

    private static func combine(_ lhs: FolderStatistics, _ rhs: FolderStatistics) -> FolderStatistics {
        var result = FolderStatistics()
        result.logicalBytes = lhs.logicalBytes + rhs.logicalBytes
        result.allocatedBytes = lhs.allocatedBytes + rhs.allocatedBytes
        result.fileCount = lhs.fileCount + rhs.fileCount
        result.folderCount = lhs.folderCount + rhs.folderCount
        result.symbolicLinkCount = lhs.symbolicLinkCount + rhs.symbolicLinkCount
        result.inaccessibleCount = lhs.inaccessibleCount + rhs.inaccessibleCount
        result.isComplete = false
        result.isCancelled = lhs.isCancelled || rhs.isCancelled
        return result
    }
}

private struct SelectionPropertiesView: View {
    @ObservedObject var model: SelectionPropertiesModel
    let close: () -> Void

    private var totals: FolderStatistics { model.statistics }
    private var hasCalculation: Bool {
        model.isCalculating || totals.isComplete || totals.isCancelled
    }
    private var partial: Bool {
        hasCalculation && (totals.inaccessibleCount > 0 || totals.isCancelled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "square.stack")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.urls.count) selected items")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Combined properties")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("SELECTION")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("ITEMS")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(model.urls, id: \.path) { url in
                            Text(url.path)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(url.path)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            HStack(spacing: 12) {
                sizeCard("Total size", bytes: hasCalculation ? totals.logicalBytes : nil)
                sizeCard("Size on disk", bytes: hasCalculation ? totals.allocatedBytes : nil)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                detail("Files", hasCalculation ? totals.fileCount.formatted() : "Not calculated")
                detail("Folders", hasCalculation ? totals.folderCount.formatted() : "Not calculated")
                if totals.symbolicLinkCount > 0 {
                    detail("Symbolic links", totals.symbolicLinkCount.formatted())
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    if model.isCalculating {
                        ProgressView().controlSize(.small)
                        Text("Calculating \(model.completedRoots + 1) of \(model.urls.count)…")
                    } else if hasCalculation {
                        Image(systemName: partial ? "exclamationmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(partial ? Color.orange : Color.green)
                        Text(partial ? "Partial combined totals" : "Combined calculation complete")
                    } else {
                        Text("Combined sizes are calculated only on request.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isCalculating {
                        Button("Stop") { model.stopCalculation() }
                    } else {
                        Button(totals.isComplete ? "Recalculate" : "Calculate") {
                            model.calculateTotals()
                        }
                        .disabled(!model.canCalculate)
                    }
                }
                .font(.system(size: 12, weight: .medium))

                if let currentItem = model.currentItem {
                    Text(currentItem)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if totals.inaccessibleCount > 0 {
                    Text("\(totals.inaccessibleCount.formatted()) items could not be read. Totals exclude inaccessible contents.")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if totals.isCancelled {
                    Text("Calculation stopped. The displayed combined totals are partial.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text("Includes hidden files and package contents. Symbolic links are counted without following their targets.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Copy Paths") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.urls.map(\.path).joined(separator: "\n"), forType: .string)
                }
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func sizeCard(_ title: String, bytes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.system(size: 25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(hasCalculation && !partial ? Color.primary : Color.secondary)
            Text(bytes.map(ByteFormat.exact) ?? "Not calculated")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    private func detail(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }.font(.system(size: 12))
    }
}
