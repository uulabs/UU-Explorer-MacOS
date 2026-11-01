import AppKit
import ExplorerCore
import Foundation

@MainActor
final class UpdateService {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/uulabs/UU-Explorer-MacOS/releases/latest")!
    static let repositoryURL = URL(string: "https://github.com/uulabs/UU-Explorer-MacOS")!
    static let expectedBundleIdentifier = "com.uulabs.uuexplorer"
    static let expectedTeamIdentifier = "V726L7NR7H"
    static let autoCheckDefaultsKey = "UUExplorer.autoUpdateChecks"
    static let lastCheckDefaultsKey = "UUExplorer.lastUpdateCheck"

    private let defaults: UserDefaults
    private weak var window: NSWindow?
    private var isChecking = false
    private var progressController: UpdateProgressWindowController?

    init(window: NSWindow?, defaults: UserDefaults = .standard) {
        self.window = window
        self.defaults = defaults
    }

    var autoChecksEnabled: Bool {
        get { defaults.object(forKey: Self.autoCheckDefaultsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.autoCheckDefaultsKey) }
    }

    var currentVersionDescription: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    func checkAutomatically() async {
        guard autoChecksEnabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckDefaultsKey) as? Date,
           Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        await performCheck(manual: false)
    }

    func checkForUpdates(manual: Bool = true) {
        Task { [weak self] in
            await self?.performCheck(manual: manual)
        }
    }

    private func performCheck(manual: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            var releaseRequest = request
            releaseRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            releaseRequest.setValue("UU-Explorer/\(currentVersionDescription)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: releaseRequest)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw UpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            defaults.set(Date(), forKey: Self.lastCheckDefaultsKey)
            guard let update = UpdateReleaseSelector.select(from: release),
                  let current = AppVersion(currentVersionDescription) else {
                throw UpdateError.invalidRelease
            }
            guard current < update.version else {
                if manual { showUpToDate(current: current, latest: update.version) }
                return
            }
            presentUpdate(update, current: current)
        } catch {
            if manual {
                presentError(error)
            } else {
                NSLog("UU Explorer update check failed: \(error.localizedDescription)")
            }
        }
    }

    private func presentUpdate(_ update: UpdateRelease, current: AppVersion) {
        let notes = update.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortened = notes.count > 900 ? String(notes.prefix(900)) + "\n…" : notes
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "UU Explorer \(update.version) is available"
        alert.informativeText = """
        You’re running \(current). The update is downloaded from GitHub, checked against its published SHA-256, and verified against UULabs’ signing identity before installation.

        \(shortened.isEmpty ? "See the release page for details." : shortened)
        """
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")
        present(alert) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                Task { [weak self] in await self?.downloadAndInstall(update) }
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(update.pageURL)
            default:
                break
            }
        }
    }

    private func showUpToDate(current: AppVersion, latest: AppVersion) {
        let alert = NSAlert()
        alert.messageText = "You’re up to date"
        alert.informativeText = "UU Explorer \(current) is the latest version available on GitHub."
        alert.addButton(withTitle: "OK")
        present(alert)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases")
        present(alert) { response in
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(Self.repositoryURL.appendingPathComponent("releases"))
            }
        }
    }

    private func downloadAndInstall(_ update: UpdateRelease) async {
        let progress = UpdateProgressWindowController(title: "Updating UU Explorer")
        progressController = progress
        progress.showWindow(nil)
        progress.window?.center()
        progress.window?.makeKeyAndOrderFront(nil)
        progress.setStatus("Downloading \(update.archiveName)…")

        do {
            guard update.archiveURL.scheme?.lowercased() == "https",
                  update.checksumURL.scheme?.lowercased() == "https" else {
                throw UpdateError.insecureURL
            }

            let (archiveData, archiveResponse) = try await URLSession.shared.data(from: update.archiveURL)
            guard let archiveHTTP = archiveResponse as? HTTPURLResponse, archiveHTTP.statusCode == 200 else {
                throw UpdateError.httpStatus((archiveResponse as? HTTPURLResponse)?.statusCode ?? -1)
            }
            guard archiveData.count > 0, archiveData.count <= 200_000_000 else {
                throw UpdateError.downloadSize
            }

            progress.setStatus("Verifying checksum…")
            let (checksumData, checksumResponse) = try await URLSession.shared.data(from: update.checksumURL)
            guard let checksumHTTP = checksumResponse as? HTTPURLResponse, checksumHTTP.statusCode == 200 else {
                throw UpdateError.httpStatus((checksumResponse as? HTTPURLResponse)?.statusCode ?? -1)
            }
            guard let checksumText = String(data: checksumData, encoding: .utf8),
                  let expected = SHA256Checksum.parseSidecar(checksumText),
                  SHA256Checksum.verify(data: archiveData, expectedHex: expected) else {
                throw UpdateError.checksumMismatch
            }

            let support = try updatesDirectory()
            let staging = support.appendingPathComponent("\(update.tag)-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let archive = staging.appendingPathComponent(update.archiveName)
            try archiveData.write(to: archive, options: .atomic)

            progress.setStatus("Expanding update…")
            try await runDetached("/usr/bin/ditto", ["-x", "-k", archive.path, staging.path])
            let appURL = try verifyExtractedApp(in: staging, expectedVersion: update.version)

            progress.setStatus("Update verified")
            progress.dismiss()
            progressController = nil
            confirmInstall(update: update, stagedApp: appURL, staging: staging)
        } catch {
            progress.dismiss()
            progressController = nil
            presentError(error)
        }
    }

    private func verifyExtractedApp(in staging: URL, expectedVersion: AppVersion) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let apps = contents.filter { $0.pathExtension.lowercased() == "app" }
        guard apps.count == 1, let appURL = apps.first else {
            throw UpdateError.invalidBundle
        }
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == Self.expectedBundleIdentifier,
              let versionString = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let version = AppVersion(versionString),
              version == expectedVersion else {
            throw UpdateError.invalidBundle
        }

        let verify = try Self.runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        guard verify.status == 0 else { throw UpdateError.invalidSignature }
        let details = try Self.runCommand("/usr/bin/codesign", ["-dv", "--verbose=4", appURL.path])
        guard details.output.contains("Identifier=\(Self.expectedBundleIdentifier)"),
              details.output.contains("TeamIdentifier=\(Self.expectedTeamIdentifier)") else {
            throw UpdateError.invalidSignature
        }
        _ = try? Self.runCommand("/usr/bin/xattr", ["-dr", "com.apple.quarantine", appURL.path])
        return appURL
    }

    private func confirmInstall(update: UpdateRelease, stagedApp: URL, staging: URL) {
        let currentApp = Bundle.main.bundleURL.standardizedFileURL
        let parent = currentApp.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "The update is ready, but this location isn’t writable"
            alert.informativeText = "Move UU Explorer to /Applications or another writable folder, then download \(update.version) from GitHub."
            alert.addButton(withTitle: "Open Releases")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(update.pageURL)
                }
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = "Install UU Explorer \(update.version)?"
        alert.informativeText = "UU Explorer will quit, install the verified update, and reopen. Your theme, tabs, and settings are kept."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Cancel")
        present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.launchInstaller(stagedApp: stagedApp, staging: staging, currentApp: currentApp)
        }
    }

    private func launchInstaller(stagedApp: URL, staging: URL, currentApp: URL) {
        let script = staging.appendingPathComponent("install-update.sh")
        let log = staging.appendingPathComponent("install.log")
        let scriptText = """
        #!/bin/sh
        set -u
        PID="$1"
        APP="$2"
        STAGED="$3"
        LOG="$4"
        while /bin/kill -0 "$PID" 2>/dev/null; do /bin/sleep 0.25; done
        PARENT="${APP%/*}"
        NEW="$PARENT/.UU Explorer.update.$$"
        OLD="$PARENT/.UU Explorer.old.$$"
        {
          /bin/rm -rf "$NEW" "$OLD"
          /usr/bin/ditto "$STAGED" "$NEW" || exit 10
          if [ -e "$APP" ]; then /bin/mv "$APP" "$OLD" || exit 11; fi
          if /bin/mv "$NEW" "$APP"; then
            /bin/rm -rf "$OLD"
            /usr/bin/open "$APP"
          else
            if [ -e "$OLD" ]; then /bin/mv "$OLD" "$APP"; fi
            /usr/bin/open "$APP"
            exit 12
          fi
        } >>"$LOG" 2>&1
        """
        do {
            try scriptText.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                script.path,
                String(ProcessInfo.processInfo.processIdentifier),
                currentApp.path,
                stagedApp.path,
                log.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApp.terminate(nil)
        } catch {
            presentError(error)
        }
    }

    private func updatesDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support
            .appendingPathComponent("UU Explorer", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func runDetached(_ executable: String, _ arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let result = try Self.runCommand(executable, arguments)
            guard result.status == 0 else {
                throw UpdateError.commandFailed(result.output.isEmpty ? "The archive could not be expanded." : result.output)
            }
        }.value
    }

    nonisolated private static func runCommand(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw UpdateError.commandFailed(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }

    private func present(
        _ alert: NSAlert,
        completion: ((NSApplication.ModalResponse) -> Void)? = nil
    ) {
        if let window {
            alert.beginSheetModal(for: window) { response in
                completion?(response)
            }
        } else {
            let response = alert.runModal()
            completion?(response)
        }
    }
}

private struct CommandResult {
    let status: Int32
    let output: String
}

private enum UpdateError: LocalizedError {
    case httpStatus(Int)
    case invalidRelease
    case insecureURL
    case downloadSize
    case checksumMismatch
    case invalidBundle
    case invalidSignature
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "GitHub returned HTTP \(code)."
        case .invalidRelease:
            return "No signed update archive with a checksum was found in the latest release."
        case .insecureURL:
            return "The update URL is not HTTPS."
        case .downloadSize:
            return "The downloaded update has an unexpected size."
        case .checksumMismatch:
            return "The update checksum did not match."
        case .invalidBundle:
            return "The downloaded archive does not contain the expected UU Explorer version."
        case .invalidSignature:
            return "The downloaded app is not signed by UULabs."
        case .commandFailed(let message):
            return message.isEmpty ? "The update operation failed." : message
        }
    }
}

@MainActor
private final class UpdateProgressWindowController: NSWindowController {
    private let statusLabel = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()

    init(title: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 130),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let stack = NSStackView(views: [spinner, statusLabel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])
        window.contentView = content
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func dismiss() {
        spinner.stopAnimation(nil)
        window?.orderOut(nil)
        window?.close()
    }
}
