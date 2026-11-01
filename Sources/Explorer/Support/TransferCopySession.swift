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

@MainActor
final class TransferCopySession {
    let source: URL
    let target: URL
    let totalBytes: Int64
    let verifyAfterCopy: Bool

    private var process: Process?
    private var cancelled = false
    private(set) var isPaused = false

    init(source: URL, target: URL, totalBytes: Int64, verifyAfterCopy: Bool) {
        self.source = source
        self.target = target
        self.totalBytes = totalBytes
        self.verifyAfterCopy = verifyAfterCopy
    }

    func start(
        onProgress: @escaping @MainActor (Int64) -> Void,
        onVerification: @escaping @MainActor (Bool) -> Void
    ) async throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw TransferCopyError.missingSource
        }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw TransferCopyError.targetExists
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "--rsrc", "--extattr", "--acl", "--qtn",
            source.path,
            target.path
        ]
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        self.process = process
        try process.run()

        var lastReported: Int64 = -1
        while process.isRunning {
            try? await Task.sleep(nanoseconds: 220_000_000)
            if cancelled {
                stopProcess(force: true)
                break
            }
            let copied = await Task.detached(priority: .utility) {
                TransferMetrics.totalLogicalBytes(at: self.target)
            }.value
            if copied != lastReported {
                lastReported = copied
                onProgress(min(copied, max(totalBytes, 1)))
            }
        }
        process.waitUntilExit()
        let finalCopied = await Task.detached(priority: .utility) {
            TransferMetrics.totalLogicalBytes(at: self.target)
        }.value
        onProgress(min(finalCopied, max(totalBytes, 1)))

        if cancelled {
            throw TransferCopyError.cancelled
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw TransferCopyError.failed(message.isEmpty ? "The copy operation failed." : message)
        }

        if verifyAfterCopy {
            onVerification(true)
            let verified = await Task.detached(priority: .utility) {
                TransferVerifier.verify(source: self.source, target: self.target)
            }.value
            onVerification(false)
            guard verified else { throw TransferCopyError.verificationFailed }
        }
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
