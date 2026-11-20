import Darwin
import ExplorerCore
import Foundation

enum TransferCopyError: LocalizedError {
    case cancelled
    case failed(String)
    case verificationFailed
    case missingSource
    case targetExists

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Transfer cancelled."
        case .failed(let message): return message
        case .verificationFailed: return "Verification failed; the copied data does not match the source."
        case .missingSource: return "The source no longer exists."
        case .targetExists: return "The destination already exists."
        }
    }
}

struct DittoOutputParser {
    struct Result {
        let copiedBytes: Int64
        let diagnostics: String
    }

    let source: URL
    let sourceIsDirectory: Bool
    private(set) var copiedBytes: Int64 = 0
    private var pending = Data()
    private var diagnostics: [String] = []

    var result: Result {
        Result(copiedBytes: copiedBytes, diagnostics: diagnostics.joined(separator: "\n"))
    }

    mutating func consume(_ data: Data) -> Bool {
        pending.append(data)
        var start = pending.startIndex
        var changed = false
        while let newline = pending[start...].firstIndex(of: 0x0a) {
            changed = processLine(pending[start..<newline]) || changed
            start = pending.index(after: newline)
        }
        if start > pending.startIndex {
            pending.removeSubrange(..<start)
        }
        return changed
    }

    mutating func finish() {
        guard !pending.isEmpty else { return }
        _ = processLine(pending)
        pending.removeAll()
    }

    mutating func appendDiagnostic(_ message: String) {
        diagnostics.append(message)
    }

    private mutating func processLine(_ data: Data) -> Bool {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        guard !line.isEmpty else { return false }

        if line.contains(" bytes for ") {
            guard let count = Self.copyByteCount(in: line) else {
                diagnostics.append(line)
                return false
            }
            copiedBytes += count
            return count > 0
        }

        for prefix in ["hardlinked ", "cloned "] where line.hasPrefix(prefix) {
            var relativePath = String(line.dropFirst(prefix.count))
            while relativePath.hasPrefix("./") { relativePath.removeFirst(2) }
            let url = sourceIsDirectory ? source.appendingPathComponent(relativePath) : source
            let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
            guard !relativePath.isEmpty,
                  sourceIsDirectory || relativePath == source.lastPathComponent,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                diagnostics.append(line)
                return false
            }
            let count = Int64(values.fileSize ?? 0)
            copiedBytes += count
            return count > 0
        }

        if line.hasPrefix(">>> Copying ") {
            return false
        }
        if line.hasPrefix("linked ") {
            var relativePath = String(line.dropFirst("linked ".count))
            while relativePath.hasPrefix("./") { relativePath.removeFirst(2) }
            let url = sourceIsDirectory ? source.appendingPathComponent(relativePath) : source
            guard !relativePath.isEmpty,
                  sourceIsDirectory || relativePath == source.lastPathComponent,
                  let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink == true else {
                diagnostics.append(line)
                return false
            }
            return false
        }
        for prefix in ["copying file ", "copying symlink "] where line.hasPrefix(prefix) {
            if line.hasSuffix(" ... ") || line.hasSuffix(" ...") {
                return false
            }
        }

        diagnostics.append(line)
        return false
    }

    private static func copyByteCount(in line: String) -> Int64? {
        let marker = " bytes for "
        guard let markerRange = line.range(of: marker),
              !line[markerRange.upperBound...].isEmpty else { return nil }
        let prefix = line[..<markerRange.lowerBound]
        let countStart = prefix.lastIndex(of: " ").map { prefix.index(after: $0) } ?? prefix.startIndex
        guard let count = Int64(prefix[countStart...]), count >= 0 else { return nil }
        let statusEnd = countStart == prefix.startIndex ? countStart : prefix.index(before: countStart)
        let status = prefix[..<statusEnd]
        guard status.isEmpty ||
                status.hasPrefix("copying file ") ||
                status.hasPrefix("hardlinked ") ||
                status.hasPrefix("cloned ") else { return nil }
        return count
    }
}

@MainActor
final class TransferCopySession {
    let source: URL
    let target: URL
    let totalBytes: Int64
    let verifyAfterCopy: Bool

    private let processOverride: Process?
    private let progressPollIntervalNanoseconds: UInt64
    private var process: Process?
    private var cancelled = false
    private(set) var isPaused = false

    init(
        source: URL,
        target: URL,
        totalBytes: Int64,
        verifyAfterCopy: Bool,
        progressPollIntervalNanoseconds: UInt64 = 220_000_000,
        processOverride: Process? = nil
    ) {
        self.source = source
        self.target = target
        self.totalBytes = totalBytes
        self.verifyAfterCopy = verifyAfterCopy
        self.progressPollIntervalNanoseconds = progressPollIntervalNanoseconds
        self.processOverride = processOverride
    }

    func start(
        onProgress: @escaping @MainActor (Int64) -> Void,
        onVerification: @escaping @MainActor (Bool) -> Void
    ) async throws {
        let source = source
        let target = target
        let preparation = await Task.detached(priority: .utility) {
            var isDirectory: ObjCBool = false
            let sourceExists = FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
            guard sourceExists else { return (false, false, false) }
            let targetExists = FileManager.default.fileExists(atPath: target.path)
            return (true, targetExists, isDirectory.boolValue)
        }.value
        guard !cancelled else {
            throw TransferCopyError.cancelled
        }
        guard preparation.0 else {
            throw TransferCopyError.missingSource
        }
        guard !preparation.1 else {
            throw TransferCopyError.targetExists
        }

        let process = processOverride ?? Process()
        if processOverride == nil {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = [
                "-V", "--rsrc", "--extattr", "--acl", "--qtn",
                source.path,
                target.path
            ]
        }
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        self.process = process
        guard !cancelled else {
            throw TransferCopyError.cancelled
        }
        try process.run()

        let outputTask = Task.detached(priority: .utility) {
            await Self.readOutput(
                from: errorPipe.fileHandleForReading,
                source: source,
                sourceIsDirectory: preparation.2,
                onProgress: onProgress
            )
        }

        var lastSampledBytes: Int64 = 0
        while process.isRunning {
            try? await Task.sleep(nanoseconds: progressPollIntervalNanoseconds)
            if cancelled {
                stopProcess(force: true)
                break
            }
            if !preparation.2 {
                let copied = await Task.detached(priority: .utility) {
                    Self.regularFileSize(at: target)
                }.value
                if let copied, copied != lastSampledBytes {
                    lastSampledBytes = copied
                    onProgress(min(copied, max(totalBytes, 1)))
                }
            }
        }
        process.waitUntilExit()
        let output = await outputTask.value

        if cancelled || process.terminationStatus != 0 {
            onProgress(min(max(output.copiedBytes, lastSampledBytes), max(totalBytes, 1)))
        }
        if cancelled {
            throw TransferCopyError.cancelled
        }
        guard process.terminationStatus == 0 else {
            let message = output.diagnostics.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TransferCopyError.failed(message.isEmpty ? "The copy operation failed." : message)
        }
        onProgress(min(totalBytes, max(totalBytes, 1)))

        if verifyAfterCopy {
            onVerification(true)
            let verified = await Task.detached(priority: .utility) {
                TransferVerifier.verify(source: self.source, target: self.target)
            }.value
            onVerification(false)
            guard verified else { throw TransferCopyError.verificationFailed }
        }
    }

    private nonisolated static func regularFileSize(at url: URL) -> Int64? {
        var fileInfo = stat()
        guard stat(url.path, &fileInfo) == 0,
              fileInfo.st_mode & S_IFMT == S_IFREG else { return nil }
        return Int64(fileInfo.st_size)
    }

    private nonisolated static func readOutput(
        from handle: FileHandle,
        source: URL,
        sourceIsDirectory: Bool,
        onProgress: @escaping @MainActor (Int64) -> Void
    ) async -> DittoOutputParser.Result {
        var parser = DittoOutputParser(source: source, sourceIsDirectory: sourceIsDirectory)
        var lastReportTime = Date.distantPast
        defer { try? handle.close() }

        do {
            while let data = try handle.read(upToCount: 16_384), !data.isEmpty {
                guard parser.consume(data) else { continue }
                let now = Date()
                guard now.timeIntervalSince(lastReportTime) >= 0.15 else { continue }
                lastReportTime = now
                await onProgress(parser.copiedBytes)
            }
        } catch {
            parser.appendDiagnostic(error.localizedDescription)
        }
        parser.finish()
        return parser.result
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        stopProcess(force: false)
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, SIGCONT)
    }

    func cancel() {
        cancelled = true
        stopProcess(force: true)
    }

    private func stopProcess(force: Bool) {
        guard let process, process.isRunning else { return }
        kill(process.processIdentifier, force ? SIGKILL : SIGSTOP)
    }
}
