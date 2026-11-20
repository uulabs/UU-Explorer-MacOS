import ExplorerCore
import Foundation

final class SearchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var activeProcess: Process?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func register(_ process: Process) {
        lock.lock()
        let shouldTerminate = value
        if !shouldTerminate {
            activeProcess = process
        }
        lock.unlock()
        if shouldTerminate, process.isRunning {
            process.terminate()
        }
    }

    func unregister(_ process: Process) {
        lock.lock()
        if activeProcess === process {
            activeProcess = nil
        }
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        value = true
        let process = activeProcess
        lock.unlock()
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

struct SearchUpdate: Sendable {
    let items: [FileItem]
    let scanned: Int
    let isFinal: Bool
}

enum SearchService {
    static func searchStream(
        root: URL,
        query: String,
        filter: SearchFilter,
        includeHidden: Bool,
        limit: Int = 2_000,
        cancellation: SearchCancellation
    ) -> AsyncStream<SearchUpdate> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || filter.isActive else {
            return AsyncStream { $0.finish() }
        }

        if !trimmed.isEmpty && filter.textMode != .name {
            return AsyncStream { continuation in
                let task = Task.detached(priority: .userInitiated) {
                    let results = await search(
                        root: root,
                        query: trimmed,
                        filter: filter,
                        includeHidden: includeHidden,
                        limit: limit,
                        cancellation: cancellation
                    )
                    guard !cancellation.isCancelled else {
                        continuation.finish()
                        return
                    }
                    continuation.yield(SearchUpdate(items: results, scanned: results.count, isFinal: true))
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in
                    cancellation.cancel()
                    task.cancel()
                }
            }
        }

        return AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                var lastScanned = 0
                _ = FileSystemService.search(
                    at: root,
                    matching: trimmed,
                    includeHidden: includeHidden,
                    filter: filter,
                    limit: limit,
                    isCancelled: { cancellation.isCancelled },
                    onProgress: { scanned, newItems in
                        lastScanned = scanned
                        guard !cancellation.isCancelled else { return }
                        continuation.yield(SearchUpdate(items: newItems, scanned: scanned, isFinal: false))
                    }
                )
                guard !cancellation.isCancelled else {
                    continuation.finish()
                    return
                }
                continuation.yield(SearchUpdate(items: [], scanned: lastScanned, isFinal: true))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                cancellation.cancel()
                task.cancel()
            }
        }
    }

    static func search(
        root: URL,
        query: String,
        filter: SearchFilter,
        includeHidden: Bool,
        limit: Int = 2_000,
        cancellation: SearchCancellation = SearchCancellation()
    ) async -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cancellation.isCancelled, !trimmed.isEmpty || filter.isActive else { return [] }

        if !trimmed.isEmpty && (filter.textMode == .content || filter.textMode == .nameAndContent) {
            let spotlight = spotlightSearch(
                root: root,
                query: trimmed,
                includeHidden: includeHidden,
                filter: filter,
                limit: limit,
                cancellation: cancellation
            )
            guard !cancellation.isCancelled else { return [] }
            if filter.textMode == .content {
                return spotlight
            }
            let names = FileSystemService.search(
                at: root,
                matching: trimmed,
                includeHidden: includeHidden,
                filter: filter,
                limit: limit,
                isCancelled: { cancellation.isCancelled }
            )
            guard !cancellation.isCancelled else { return [] }
            var seen = Set<String>()
            var results: [FileItem] = []
            for item in names + spotlight {
                guard !cancellation.isCancelled else { return [] }
                if seen.insert(item.id).inserted {
                    results.append(item)
                    if results.count >= limit { break }
                }
            }
            return results
        }

        return FileSystemService.search(
            at: root,
            matching: trimmed,
            includeHidden: includeHidden,
            filter: filter,
            limit: limit,
            isCancelled: { cancellation.isCancelled }
        )
    }

    private static func spotlightSearch(
        root: URL,
        query: String,
        includeHidden: Bool,
        filter: SearchFilter,
        limit: Int,
        cancellation: SearchCancellation
    ) -> [FileItem] {
        guard !query.isEmpty, !cancellation.isCancelled else { return [] }
        let paths = runMDFind(root: root, query: query, limit: limit, cancellation: cancellation)
        guard !paths.isEmpty, !cancellation.isCancelled else { return [] }

        var items: [FileItem] = []
        for path in paths {
            guard !cancellation.isCancelled else { return [] }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let item = FileSystemService.fileItem(at: url, includeHidden: includeHidden),
                  !item.isDirectory,
                  filter.matches(item) else { continue }
            items.append(item)
        }
        return cancellation.isCancelled ? [] : items
    }

    private static func runMDFind(
        root: URL,
        query: String,
        limit: Int,
        cancellation: SearchCancellation
    ) -> [String] {
        guard limit > 0, !cancellation.isCancelled else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", root.path, query]

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("uu-spotlight-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: output) }
        guard let handle = try? FileHandle(forWritingTo: output) else { return [] }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        defer { try? handle.close() }

        do {
            guard !cancellation.isCancelled else { return [] }
            try process.run()
            cancellation.register(process)
            defer { cancellation.unregister(process) }
            process.waitUntilExit()
        } catch {
            return []
        }
        guard !cancellation.isCancelled, process.terminationStatus == 0 else { return [] }
        guard let data = try? Data(contentsOf: output),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var paths: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard !cancellation.isCancelled else { return [] }
            let path = String(line)
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            paths.append(path)
            if paths.count >= limit { break }
        }
        return cancellation.isCancelled ? [] : paths
    }
}
