import ExplorerCore
import Foundation
import SwiftUI

enum FileOperationKind: String {
    case copy
    case move
    case compress
    case extract

    var title: String {
        switch self {
        case .copy: return "Copying"
        case .move: return "Moving"
        case .compress: return "Compressing"
        case .extract: return "Extracting"
        }
    }

    var symbol: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "arrow.right.doc.on.clipboard"
        case .compress: return "archivebox"
        case .extract: return "archivebox.fill"
        }
    }

    var isCancellable: Bool { true }
}

enum FileOperationState {
    case queued
    case running
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .queued, .running: return false
        }
    }
}

struct FileOperation: Identifiable {
    let id: UUID
    let kind: FileOperationKind
    var title: String
    var destination: URL
    var total: Int
    var completed: Int = 0
    var currentItem: String?
    var state: FileOperationState = .queued
    var error: String?

    var progress: Double? {
        guard total > 0 else { return nil }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

struct TransferPair {
    let source: URL
    let target: URL
}

struct TransferOutcome {
    var created: [URL]
    var pairs: [TransferPair]
    var failures: [String]
    var cancelled: Bool
}

enum ConflictChoice {
    case replace
    case keepBoth
    case skip
}

struct FileConflict: Identifiable {
    let id = UUID()
    let operationID: UUID
    let source: URL
    let destination: URL
    let continuation: CheckedContinuation<ConflictChoice, Never>
}

@MainActor
final class FileOperationQueue: ObservableObject {
    @Published private(set) var operations: [FileOperation] = []
    @Published var conflict: FileConflict?

    private enum JobWork {
        case transfer(sources: [URL])
        case compress(source: URL)
        case extract(archive: URL)
    }

    private struct Job {
        let id: UUID
        let kind: FileOperationKind
        let destination: URL
        let total: Int
        let work: JobWork
        let completion: (TransferOutcome) -> Void
    }

    private var pending: [Job] = []
    private var activeID: UUID?
    private var activeTask: Task<Void, Never>?
    private var cancelledIDs = Set<UUID>()
    private var conflictPolicies: [UUID: ConflictChoice] = [:]

    func enqueueTransfer(
        sources: [URL],
        destination: URL,
        isMove: Bool,
        completion: @escaping (TransferOutcome) -> Void
    ) {
        let sources = sources.map(\.standardizedFileURL)
        guard !sources.isEmpty else {
            completion(TransferOutcome(created: [], pairs: [], failures: [], cancelled: false))
            return
        }
        let id = UUID()
        let kind: FileOperationKind = isMove ? .move : .copy
        let operation = FileOperation(
            id: id,
            kind: kind,
            title: "\(kind.title) \(sources.count) item\(sources.count == 1 ? "" : "s")",
            destination: destination.standardizedFileURL,
            total: sources.count
        )
        operations.append(operation)
        pending.append(Job(
            id: id,
            kind: kind,
            destination: destination.standardizedFileURL,
            total: sources.count,
            work: .transfer(sources: sources),
            completion: completion
        ))
        startNext()
    }

    func enqueueArchive(
        kind: FileOperationKind,
        source: URL,
        destination: URL,
        completion: @escaping (TransferOutcome) -> Void
    ) {
        guard kind == .compress || kind == .extract else {
            completion(TransferOutcome(created: [], pairs: [], failures: ["Unsupported operation"], cancelled: false))
            return
        }
        let id = UUID()
        let operation = FileOperation(
            id: id,
            kind: kind,
            title: "\(kind.title) \(source.lastPathComponent)",
            destination: destination.standardizedFileURL,
            total: 1
        )
        operations.append(operation)
        pending.append(Job(
            id: id,
            kind: kind,
            destination: destination.standardizedFileURL,
            total: 1,
            work: kind == .compress ? .compress(source: source) : .extract(archive: source),
            completion: completion
        ))
        startNext()
    }

    func cancel(_ id: UUID) {
        cancelledIDs.insert(id)
        if let index = pending.firstIndex(where: { $0.id == id }) {
            let job = pending.remove(at: index)
            update(id) { operation in
                operation.state = .cancelled
                operation.error = "Cancelled"
            }
            job.completion(TransferOutcome(created: [], pairs: [], failures: [], cancelled: true))
            return
        }

        if activeID == id, let conflict, conflict.operationID == id {
            self.conflict = nil
            conflict.continuation.resume(returning: .skip)
        }
        if activeID == id,
           let operation = operations.first(where: { $0.id == id }),
           operation.kind == .compress || operation.kind == .extract {
            ArchiveService.cancelActiveArchive()
        }

    }

    func resolveConflict(_ choice: ConflictChoice, applyToAll: Bool) {
        guard let conflict else { return }
        if applyToAll {
            conflictPolicies[conflict.operationID] = choice
        }
        self.conflict = nil
        conflict.continuation.resume(returning: choice)
    }

    func cancelConflict() {
        guard let conflict else { return }
        cancelledIDs.insert(conflict.operationID)
        self.conflict = nil
        conflict.continuation.resume(returning: .skip)
    }

    func dismiss(_ id: UUID) {
        operations.removeAll { $0.id == id }
    }

    private func startNext() {
        guard activeTask == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        guard !cancelledIDs.contains(job.id) else {
            update(job.id) { operation in
                operation.state = .cancelled
                operation.error = "Cancelled"
            }
            job.completion(TransferOutcome(created: [], pairs: [], failures: [], cancelled: true))
            startNext()
            return
        }

        activeID = job.id
        update(job.id) { operation in
            operation.state = .running
            operation.currentItem = nil
        }
        activeTask = Task { [weak self] in
            guard let self else { return }
            await self.run(job)
            self.activeID = nil
            self.activeTask = nil
            self.startNext()
        }
    }

    private func run(_ job: Job) async {
        var created: [URL] = []
        var pairs: [TransferPair] = []
        var failures: [String] = []
        var wasCancelled = false

        func finish() {
            let state: FileOperationState = wasCancelled
                ? .cancelled
                : (failures.isEmpty ? .completed : .failed)
            update(job.id) { operation in
                operation.state = state
                operation.currentItem = nil
                operation.error = failures.first ?? (wasCancelled ? "Cancelled" : nil)
            }
            conflictPolicies.removeValue(forKey: job.id)
            cancelledIDs.remove(job.id)
            job.completion(TransferOutcome(created: created, pairs: pairs, failures: failures, cancelled: wasCancelled))
            if state.isTerminal {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    self?.dismiss(job.id)
                }
            }
        }

        switch job.work {
        case .transfer(let sources):
            if cancelledIDs.contains(job.id) {
                wasCancelled = true
                finish()
                return
            }
            for source in sources {
                if cancelledIDs.contains(job.id) {
                    wasCancelled = true
                    break
                }
                update(job.id) { operation in
                    operation.currentItem = source.lastPathComponent
                }

                if job.kind == .move &&
                    source.deletingLastPathComponent().standardizedFileURL.path == job.destination.path {
                    update(job.id) { $0.completed += 1 }
                    continue
                }

                var target = job.destination.appendingPathComponent(source.lastPathComponent)
                if FileManager.default.fileExists(atPath: target.path) {
                    if target.standardizedFileURL.path == source.standardizedFileURL.path {
                        target = FileName.uniqueDestination(for: source, in: job.destination, duplicate: false)
                    } else {
                        let choice = await conflictChoice(for: job, source: source, destination: target)
                        if cancelledIDs.contains(job.id) {
                            wasCancelled = true
                            break
                        }
                        switch choice {
                        case .skip:
                            update(job.id) { $0.completed += 1 }
                            continue
                        case .keepBoth:
                            target = FileName.uniqueDestination(for: source, in: job.destination, duplicate: false)
                        case .replace:
                            do {
                                _ = try await Task.detached(priority: .userInitiated) {
                                    try TrashService.recycle(target)
                                }.value
                            } catch {
                                failures.append("\(target.lastPathComponent): \(error.localizedDescription)")
                                update(job.id) { $0.completed += 1 }
                                continue
                            }
                        }
                    }
                }

                do {
                    let isMove = job.kind == .move
                    try await Task.detached(priority: .userInitiated) {
                        if isMove {
                            try FileManager.default.moveItem(at: source, to: target)
                        } else {
                            try FileManager.default.copyItem(at: source, to: target)
                        }
                    }.value
                    created.append(target)
                    pairs.append(TransferPair(source: source, target: target))
                    update(job.id) { $0.completed += 1 }
                } catch {
                    failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
                    update(job.id) { $0.completed += 1 }
                }
            }

        case .compress(let source):
            update(job.id) { $0.currentItem = source.lastPathComponent }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ArchiveService.compress(source, to: job.destination)
                }.value
                created.append(job.destination)
                pairs.append(TransferPair(source: source, target: job.destination))
                update(job.id) { $0.completed = 1 }
            } catch {
                failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }

        case .extract(let archive):
            update(job.id) { $0.currentItem = archive.lastPathComponent }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ArchiveService.extract(archive, to: job.destination)
                }.value
                update(job.id) { $0.completed = 1 }
            } catch {
                failures.append("\(archive.lastPathComponent): \(error.localizedDescription)")
            }
        }

        if cancelledIDs.contains(job.id) {
            wasCancelled = true
        }
        finish()
    }

    private func conflictChoice(for job: Job, source: URL, destination: URL) async -> ConflictChoice {
        if let policy = conflictPolicies[job.id] {
            return policy
        }
        return await withCheckedContinuation { continuation in
            conflict = FileConflict(
                operationID: job.id,
                source: source,
                destination: destination,
                continuation: continuation
            )
        }
    }

    private func update(_ id: UUID, _ mutate: (inout FileOperation) -> Void) {
        guard let index = operations.firstIndex(where: { $0.id == id }) else { return }
        mutate(&operations[index])
    }
}

struct OperationQueueOverlay: View {
    @ObservedObject var queue: FileOperationQueue
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(Array(queue.operations.suffix(3))) { operation in
                operationCard(operation)
            }
        }
        .frame(width: 340, alignment: .trailing)
        .sheet(item: $queue.conflict) { conflict in
            FileConflictSheet(queue: queue, conflict: conflict)
                .interactiveDismissDisabled()
        }
    }

    private func operationCard(_ operation: FileOperation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: operation.kind.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text(operation.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.contentText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if operation.state.isTerminal {
                    Button {
                        queue.dismiss(operation.id)
                    } label: {
                        Image(systemName: operation.state == .completed ? "checkmark" : "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(operation.state == .completed ? theme.accent : theme.contentSecondary)
                    .help("Dismiss")
                } else if operation.kind.isCancellable {
                    Button {
                        queue.cancel(operation.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.contentSecondary)
                    .help("Cancel")
                }
            }

            if operation.state == .running {
                if operation.total > 1, let progress = operation.progress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .tint(theme.accent)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                HStack(spacing: 5) {
                    Text(operation.currentItem ?? "Starting…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("\(operation.completed) of \(operation.total)")
                        .monospacedDigit()
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.contentSecondary)
            } else if operation.state == .queued {
                Text("Waiting…")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.contentSecondary)
            } else if operation.state == .failed {
                Text(operation.error ?? "Failed")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.contentSecondary)
                    .lineLimit(2)
            } else if operation.state == .cancelled {
                Text("Cancelled")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.contentSecondary)
            } else {
                Text("Complete")
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.contentSecondary)
            }
        }
        .padding(10)
        .background(theme.contentField, in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(theme.divider, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
}

struct FileConflictSheet: View {
    @ObservedObject var queue: FileOperationQueue
    let conflict: FileConflict
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var applyToAll = false

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("An item already exists")
                .font(.system(size: 15, weight: .semibold))
            Text("“\(conflict.destination.lastPathComponent)” already exists in this folder.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(conflict.source.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            Toggle("Apply to all remaining conflicts", isOn: $applyToAll)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            HStack {
                Button("Cancel Operation", role: .cancel) {
                    queue.cancelConflict()
                }
                Spacer()
                Button("Skip") {
                    queue.resolveConflict(.skip, applyToAll: applyToAll)
                }
                Button("Keep Both") {
                    queue.resolveConflict(.keepBoth, applyToAll: applyToAll)
                }
                Button("Replace", role: .destructive) {
                    queue.resolveConflict(.replace, applyToAll: applyToAll)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(theme.background)
    }
}
