import ExplorerCore
import Foundation

final class SearchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
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
                        limit: limit
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
        limit: Int = 2_000
    ) async -> [FileItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || filter.isActive else { return [] }

        if !trimmed.isEmpty && (filter.textMode == .content || filter.textMode == .nameAndContent) {
            let spotlight = await spotlightSearch(
                root: root,
                query: trimmed,
                includeHidden: includeHidden,
                filter: filter,
                limit: limit
            )
            if filter.textMode == .content {
                return spotlight
            }
            let names = await Task.detached(priority: .userInitiated) {
                FileSystemService.search(
                    at: root,
                    matching: trimmed,
                    includeHidden: includeHidden,
                    filter: filter,
                    limit: limit
                )
            }.value
            var seen = Set<String>()
            return Array((names + spotlight).filter { seen.insert($0.id).inserted }.prefix(limit))
        }

        return await Task.detached(priority: .userInitiated) {
            FileSystemService.search(
                at: root,
                matching: trimmed,
                includeHidden: includeHidden,
                filter: filter,
                limit: limit
            )
        }.value
    }

    private static func spotlightSearch(
        root: URL,
        query: String,
        includeHidden: Bool,
        filter: SearchFilter,
        limit: Int
    ) async -> [FileItem] {
        guard !query.isEmpty else { return [] }
        let paths = await Task.detached(priority: .userInitiated) {
            runMDFind(root: root, query: query, limit: limit)
        }.value
        guard !paths.isEmpty else { return [] }

        return paths.compactMap { path -> FileItem? in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard let item = FileSystemService.fileItem(at: url, includeHidden: includeHidden),
                  !item.isDirectory,
                  filter.matches(item) else { return nil }
            return item
        }
    }

    private static func runMDFind(root: URL, query: String, limit: Int) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-onlyin", root.path, query]

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("uu-spotlight-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: output) else { return [] }
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: output)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        guard let data = try? Data(contentsOf: output),
              let text = String(data: data, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var paths: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let path = String(line)
            guard !path.isEmpty, seen.insert(path).inserted else { continue }
            paths.append(path)
            if paths.count >= limit { break }
        }
        return paths
    }
}
