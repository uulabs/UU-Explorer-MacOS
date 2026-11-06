import Foundation

public enum ArchiveFormat: String, Sendable {
    case zip
    case tar
    case tarGz
    case rar
    case sevenZip

    public var title: String {
        switch self {
        case .zip: return "ZIP"
        case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"
        case .rar: return "RAR"
        case .sevenZip: return "7-Zip"
        }
    }
}

public struct ArchiveEntry: Identifiable, Hashable, Sendable {
    public let path: String
    public let isDirectory: Bool

    public var id: String { path }
    public var name: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
    public var extractionPath: String {
        isDirectory ? path + "/" : path
    }

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }
}

public enum ArchiveError: LocalizedError {
    case unsupportedFormat
    case sourceMissing(String)
    case destinationMissing(String)
    case destinationExists(String)
    case commandFailed(String)
    case toolMissing(String)
    case invalidEntry(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "That archive format isn’t supported."
        case .sourceMissing(let path):
            return "The source “\(path)” no longer exists."
        case .destinationMissing(let path):
            return "The destination “\(path)” no longer exists."
        case .destinationExists(let path):
            return "A file already exists at “\(path)”."
        case .commandFailed(let message):
            return message.isEmpty ? "The archive operation failed." : message
        case .toolMissing(let format):
            return "Extracting \(format) archives needs 7-Zip, unar, or unrar. Install one and try again."
        case .invalidEntry(let path):
            return "The archive contains an unsafe path: \(path)"
        }
    }
}

/// Small wrapper around macOS's built-in archive tools.
/// ZIP archives are created with ditto so resource forks and extended attributes survive.
public enum ArchiveService {
    private static let processLock = NSLock()
    private static var activeProcess: Process?

    /// Cancels the archive operation currently running through this service.
    public static func cancelActiveArchive() {
        processLock.lock()
        activeProcess?.terminate()
        processLock.unlock()
    }

    public static func format(for url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") { return .zip }
        if name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz") { return .tarGz }
        if name.hasSuffix(".tar") { return .tar }
        if name.hasSuffix(".rar") { return .rar }
        if name.hasSuffix(".7z") { return .sevenZip }
        return nil
    }

    public static func isArchive(_ url: URL) -> Bool {
        guard format(for: url) != nil else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    /// Returns the single top-level directory when every archive entry lives
    /// under one folder, so Extract Here can extract beside the archive instead
    /// of creating a redundant wrapper folder.
    public static func topLevelDirectoryName(_ archive: URL) -> String? {
        guard let format = format(for: archive),
              let listing = try? listEntries(archive, format: format) else { return nil }

        var firstComponents = Set<String>()
        var sawNestedEntry = false
        var sawDirectoryEntry = false

        for rawLine in listing.split(whereSeparator: \.isNewline) {
            var name = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name != "." else { continue }
            while name.hasPrefix("./") { name.removeFirst(2) }
            guard !name.isEmpty,
                  name != "__MACOSX",
                  !name.hasPrefix("__MACOSX/") else { continue }

            let components = name.split(separator: "/", omittingEmptySubsequences: true)
            guard let first = components.first else { continue }
            firstComponents.insert(String(first))
            if components.count > 1 { sawNestedEntry = true }
            if name.hasSuffix("/") { sawDirectoryEntry = true }
        }

        guard firstComponents.count == 1,
              sawNestedEntry || sawDirectoryEntry,
              let top = firstComponents.first,
              top != ".",
              top != ".." else { return nil }
        return top
    }

    /// Lists archive entries as relative paths. Missing directory entries are
    /// synthesized so the browser can show a folder hierarchy.
    public static func entries(of archive: URL) throws -> [ArchiveEntry] {
        guard let format = format(for: archive) else {
            throw ArchiveError.unsupportedFormat
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ArchiveError.sourceMissing(archive.lastPathComponent)
        }

        let listing = try listEntries(archive, format: format)
        var entries: [ArchiveEntry] = []
        var seen = Set<String>()

        func append(_ path: String, isDirectory: Bool) {
            guard validRelativePath(path), seen.insert(path).inserted else { return }
            entries.append(ArchiveEntry(path: path, isDirectory: isDirectory))
        }

        for rawLine in listing.split(whereSeparator: \.isNewline) {
            var name = String(rawLine)
            while name.hasPrefix("./") { name.removeFirst(2) }
            guard !name.isEmpty,
                  name != ".",
                  name != "__MACOSX",
                  !name.hasPrefix("__MACOSX/") else { continue }
            let isDir = name.hasSuffix("/")
            while name.hasSuffix("/") { name.removeLast() }
            guard !name.isEmpty else { continue }

            let components = name.split(separator: "/").map(String.init)
            if components.count > 1 {
                for index in 1..<components.count {
                    append(components.prefix(index).joined(separator: "/"), isDirectory: true)
                }
            }
            append(name, isDirectory: isDir)
        }

        return entries.sorted {
            if $0.path == $1.path { return $0.isDirectory && !$1.isDirectory }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }

    /// Extracts one file or directory entry into an existing destination folder.
    /// Entry paths are validated before invoking bsdtar.
    public static func extractEntry(
        _ entry: ArchiveEntry,
        from archive: URL,
        to destination: URL
    ) throws {
        guard format(for: archive) != nil else {
            throw ArchiveError.unsupportedFormat
        }
        guard validRelativePath(entry.path) else {
            throw ArchiveError.invalidEntry(entry.path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ArchiveError.destinationMissing(destination.lastPathComponent)
        }
        try run("/usr/bin/bsdtar", [
            "-xf", archive.path,
            "-C", destination.path,
            entry.extractionPath
        ])
    }

    private static func validRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(where: { $0 == ".." || $0.isEmpty })
    }

    public static func compress(_ source: URL, to destination: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ArchiveError.sourceMissing(source.lastPathComponent)
        }
        guard destination.pathExtension.lowercased() == "zip" else {
            throw ArchiveError.unsupportedFormat
        }
        guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) else {
            throw ArchiveError.destinationMissing(destination.deletingLastPathComponent().lastPathComponent)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ArchiveError.destinationExists(destination.lastPathComponent)
        }

        var arguments = ["-c", "-k", "--sequesterRsrc"]
        if isDirectory.boolValue {
            arguments.append("--keepParent")
        }
        arguments.append(contentsOf: [source.path, destination.path])
        try run("/usr/bin/ditto", arguments)
    }

    /// Creates a classic encrypted ZIP (ZipCrypto) using the system zip tool.
    /// The password is passed through argv, so this is intended for local,
    /// user-initiated archives only.
    public static func compressEncrypted(
        _ source: URL,
        to destination: URL,
        password: String
    ) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ArchiveError.sourceMissing(source.lastPathComponent)
        }
        guard destination.pathExtension.lowercased() == "zip" else {
            throw ArchiveError.unsupportedFormat
        }
        guard !password.isEmpty else {
            throw ArchiveError.commandFailed("Enter a password.")
        }
        guard FileManager.default.fileExists(atPath: destination.deletingLastPathComponent().path) else {
            throw ArchiveError.destinationMissing(destination.deletingLastPathComponent().lastPathComponent)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ArchiveError.destinationExists(destination.lastPathComponent)
        }

        do {
            try run(
                "/usr/bin/zip",
                ["-P", password, "-r", destination.path, source.lastPathComponent],
                currentDirectory: source.deletingLastPathComponent()
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    public static func extract(_ archive: URL, to destination: URL) throws {
        guard let format = format(for: archive) else {
            throw ArchiveError.unsupportedFormat
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archive.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ArchiveError.sourceMissing(archive.lastPathComponent)
        }
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ArchiveError.destinationMissing(destination.lastPathComponent)
        }

        switch format {
        case .zip:
            try run("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
        case .tar, .tarGz:
            try run("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
        case .rar:
            try extractWithExternalTool(archive, destination: destination, prefer: ["unar", "unrar", "7z", "7zz"])
        case .sevenZip:
            try extractWithExternalTool(archive, destination: destination, prefer: ["7z", "7zz", "unar"])
        }
    }

    private static func extractWithExternalTool(
        _ archive: URL,
        destination: URL,
        prefer names: [String]
    ) throws {
        var lastError: Error?
        for name in names {
            guard let tool = executable(named: name) else { continue }
            do {
                switch name {
                case "7z", "7zz":
                    try run(tool, ["x", "-y", "-o\(destination.path)", archive.path])
                case "unar":
                    try run(tool, ["-q", "-o", destination.path, archive.path])
                case "unrar":
                    try run(tool, ["x", "-o+", "-y", archive.path, destination.path + "/"])
                default:
                    continue
                }
                return
            } catch {
                lastError = error
            }
        }

        if FileManager.default.isExecutableFile(atPath: "/usr/bin/bsdtar") {
            do {
                try run("/usr/bin/bsdtar", ["-xf", archive.path, "-C", destination.path])
                return
            } catch {
                lastError = error
            }
        }

        if let lastError { throw lastError }
        throw ArchiveError.toolMissing(ArchiveService.format(for: archive)?.title ?? "RAR/7-Zip")
    }

    private static func executable(named name: String) -> String? {
        for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let path = "\(directory)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func listEntries(_ archive: URL, format: ArchiveFormat) throws -> String {
        switch format {
        case .zip:
            return try capture("/usr/bin/unzip", ["-Z1", archive.path])
        case .tar, .tarGz:
            return try capture("/usr/bin/tar", ["-tf", archive.path])
        case .rar, .sevenZip:
            return try capture("/usr/bin/bsdtar", ["-tf", archive.path])
        }
    }

    private static func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ArchiveError.commandFailed(error.localizedDescription)
        }
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ArchiveError.commandFailed("Couldn’t inspect the archive.")
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private static func run(
        _ executable: String,
        _ arguments: [String],
        currentDirectory: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        processLock.lock()
        activeProcess = process
        processLock.unlock()
        defer {
            processLock.lock()
            if activeProcess === process {
                activeProcess = nil
            }
            processLock.unlock()
        }

        do {
            try process.run()
        } catch {
            throw ArchiveError.commandFailed(error.localizedDescription)
        }
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ArchiveError.commandFailed(message)
        }
    }
}
