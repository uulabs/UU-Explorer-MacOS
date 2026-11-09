import AppKit
import Foundation

struct AndroidDevice: Identifiable, Equatable, Sendable {
    let serial: String
    let state: String
    let model: String
    let product: String
    let device: String
    let transportID: String?

    var id: String { serial }
    var isReady: Bool { state == "device" }

    var displayName: String {
        let cleaned = model.replacingOccurrences(of: "_", with: " ")
        let name = cleaned.isEmpty ? device.replacingOccurrences(of: "_", with: " ") : cleaned
        return "\(name.isEmpty ? "Android device" : name) · \(serial)"
    }
}

enum ADBError: LocalizedError {
    case notFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "adb was not found. Install Android Platform Tools or choose the adb binary."
        case .commandFailed(let message):
            return message
        }
    }
}

struct AndroidEntry: Identifiable, Equatable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isLink: Bool
    let byteSize: Int64?

    var id: String { path }
}

@MainActor
final class ADBService: ObservableObject {
    static let shared = ADBService()
    static let adbPathDefaultsKey = "UUExplorer.adbPath"

    @Published private(set) var adbPath: String?
    @Published private(set) var devices: [AndroidDevice] = []

    private init() {
        adbPath = Self.locateADB()
    }

    func refreshDevicesSync() -> [AndroidDevice] {
        if adbPath == nil { adbPath = Self.locateADB() }
        guard let path = adbPath else {
            devices = []
            return devices
        }
        let result = run(path, ["devices", "-l"], timeout: 1.5)
        devices = Self.parseDevices(result.output)
        return devices
    }

    func refreshDevices() async -> [AndroidDevice] {
        if adbPath == nil { adbPath = Self.locateADB() }
        guard let path = adbPath else {
            devices = []
            return []
        }
        let result = await Task.detached(priority: .utility) {
            Self.runStatic(path, ["devices", "-l"], timeout: 1.5)
        }.value
        let parsed = Self.parseDevices(result.output)
        devices = parsed
        return parsed
    }

    func installAPK(_ apk: URL, on device: AndroidDevice, completion: @escaping (Result<String, Error>) -> Void) {
        guard let adbPath else {
            completion(.failure(ADBError.notFound))
            return
        }
        let serial = device.serial
        let path = apk.path
        Task.detached(priority: .userInitiated) {
            let result = Self.runStatic(adbPath, ["-s", serial, "install", "-r", path], timeout: 120)
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if result.status == 0, message.localizedCaseInsensitiveContains("Success") {
                    completion(.success(message.isEmpty ? "Installed \(apk.lastPathComponent)" : message))
                } else {
                    completion(.failure(ADBError.commandFailed(message.isEmpty
                        ? "adb install failed with status \(result.status)"
                        : message)))
                }
            }
        }
    }

    func listDirectory(_ path: String, device: AndroidDevice) async throws -> [AndroidEntry] {
        guard let adbPath else { throw ADBError.notFound }
        let result = await Task.detached(priority: .userInitiated) {
            Self.runStatic(adbPath, ["-s", device.serial, "shell", "ls -la \(Self.shellQuote(path))"], timeout: 20)
        }.value
        guard result.status == 0 else { throw ADBError.commandFailed(result.output) }
        return Self.parseEntries(result.output, parent: path)
    }

    func pull(_ entry: AndroidEntry, to destination: URL, device: AndroidDevice) async throws {
        guard let adbPath else { throw ADBError.notFound }
        let result = await Task.detached(priority: .userInitiated) {
            Self.runStatic(adbPath, ["-s", device.serial, "pull", entry.path, destination.path], timeout: 180)
        }.value
        guard result.status == 0 else { throw ADBError.commandFailed(result.output) }
    }

    func push(_ localURL: URL, toRemoteDirectory remote: String, device: AndroidDevice) async throws {
        guard let adbPath else { throw ADBError.notFound }
        let target = remote.hasSuffix("/") ? remote + localURL.lastPathComponent : remote + "/" + localURL.lastPathComponent
        let result = await Task.detached(priority: .userInitiated) {
            Self.runStatic(adbPath, ["-s", device.serial, "push", localURL.path, target], timeout: 180)
        }.value
        guard result.status == 0 else { throw ADBError.commandFailed(result.output) }
    }

    func chooseADBPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose adb"
        panel.prompt = "Use adb"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.adbPathDefaultsKey)
        adbPath = url.path
    }

    static func locateADB() -> String? {
        if let stored = UserDefaults.standard.string(forKey: adbPathDefaultsKey),
           FileManager.default.isExecutableFile(atPath: stored) {
            return stored
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/adb" })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> (output: String, status: Int32) {
        Self.runStatic(executable, arguments, timeout: timeout)
    }

    nonisolated private static func runStatic(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> (output: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("uu-adb-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: outputURL) else {
            return ("Could not create adb output capture.", -1)
        }
        process.standardOutput = handle
        process.standardError = handle
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        do {
            try process.run()
        } catch {
            return (error.localizedDescription, -1)
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 1)
        }
        try? handle.synchronize()
        let data = try? Data(contentsOf: outputURL)
        return (String(data: data ?? Data(), encoding: .utf8) ?? "", process.terminationStatus)
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func parseEntries(_ output: String, parent: String) -> [AndroidEntry] {
        var entries: [AndroidEntry] = []
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("total ") { continue }
            let parts = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 8 else { continue }
            let permissions = parts[0]
            guard let kind = permissions.first, "dl-".contains(kind) else { continue }
            var name = parts[7]
            if name == "." || name == ".." { continue }
            if let arrow = name.range(of: " -> ") {
                name = String(name[..<arrow.lowerBound])
            }
            let path = parent.hasSuffix("/") ? parent + name : parent + "/" + name
            entries.append(AndroidEntry(
                name: name,
                path: path,
                isDirectory: kind == "d",
                isLink: kind == "l",
                byteSize: kind == "-" ? Int64(parts[4]) : nil
            ))
        }
        return entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func parseDevices(_ output: String) -> [AndroidDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, parts[0] != "List" else { return nil }
            let serial = parts[0]
            let state = parts[1]
            let knownStates = ["device", "unauthorized", "offline", "recovery", "sideload", "bootloader", "no"]
            guard knownStates.contains(state) else { return nil }
            var model = ""
            var product = ""
            var device = ""
            var transportID: String?
            for part in parts.dropFirst(2) {
                if part.hasPrefix("model:") { model = String(part.dropFirst(6)) }
                else if part.hasPrefix("product:") { product = String(part.dropFirst(8)) }
                else if part.hasPrefix("device:") { device = String(part.dropFirst(7)) }
                else if part.hasPrefix("transport_id:") { transportID = String(part.dropFirst(13)) }
            }
            return AndroidDevice(
                serial: serial,
                state: state,
                model: model,
                product: product,
                device: device,
                transportID: transportID
            )
        }
    }
}
