import AppKit
import ExplorerCore
import SwiftUI

@MainActor
private final class AndroidBrowserModel: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    @Published var selectedSerial: String?
    private let preferredSerial: String?
    @Published var path = "/sdcard/"
    @Published var entries: [AndroidEntry] = []
    @Published var selection = Set<String>()
    @Published var isLoading = false
    @Published var error: String?
    @Published var status: String?

    init(preferredSerial: String? = nil) {
        self.preferredSerial = preferredSerial
        self.selectedSerial = preferredSerial
    }

    var selectedDevice: AndroidDevice? {
        devices.first { $0.serial == selectedSerial }
    }

    var selectedEntries: [AndroidEntry] {
        entries.filter { selection.contains($0.id) }
    }

    func refreshDevices() {
        error = nil
        isLoading = true
        Task {
            let devices = await ADBService.shared.refreshDevices()
            self.devices = devices
            if let preferredSerial,
               devices.contains(where: { $0.serial == preferredSerial && $0.isReady }) {
                selectedSerial = preferredSerial
            } else if selectedSerial == nil || !devices.contains(where: { $0.serial == selectedSerial }) {
                selectedSerial = devices.first(where: \.isReady)?.serial
            }
            isLoading = false
            if selectedDevice != nil {
                loadPath()
            } else {
                entries = []
                error = devices.isEmpty
                    ? "No Android devices found. Enable USB debugging and authorize this computer."
                    : "No authorized Android devices. Check the authorization prompt on the phone."
            }
        }
    }

    func loadPath() {
        guard let device = selectedDevice else { return }
        let requested = path
        isLoading = true
        error = nil
        Task {
            do {
                let entries = try await ADBService.shared.listDirectory(requested, device: device)
                guard requested == path else { return }
                self.entries = entries
                self.isLoading = false
            } catch {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func navigate(to entry: AndroidEntry) {
        guard entry.isDirectory else {
            openEntry(entry)
            return
        }
        path = entry.path.hasSuffix("/") ? entry.path : entry.path + "/"
        selection = []
        loadPath()
    }

    func up() {
        guard path != "/" else { return }
        var components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return }
        components.removeLast()
        path = components.isEmpty ? "/" : "/" + components.joined(separator: "/") + "/"
        selection = []
        loadPath()
    }

    func openSelection() {
        guard selectedEntries.count == 1, let entry = selectedEntries.first else { return }
        if entry.isDirectory {
            navigate(to: entry)
        } else {
            openEntry(entry)
        }
    }

    func openEntry(_ entry: AndroidEntry) {
        guard let device = selectedDevice else { return }
        status = "Opening \(entry.name)…"
        Task {
            do {
                let cache = try Self.cacheDirectory()
                let target = cache.appendingPathComponent(entry.name)
                try await ADBService.shared.pull(entry, to: target, device: device)
                status = nil
                NSWorkspace.shared.open(target)
            } catch {
                status = nil
                self.error = error.localizedDescription
            }
        }
    }

    func pullSelection() {
        guard !selectedEntries.isEmpty, let device = selectedDevice else { return }
        let panel = NSOpenPanel()
        panel.title = "Pull from Android"
        panel.prompt = "Pull Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let entries = selectedEntries
        status = "Pulling \(entries.count) item\(entries.count == 1 ? "" : "s")…"
        error = nil
        Task {
            do {
                for entry in entries {
                    try await ADBService.shared.pull(entry, to: destination, device: device)
                }
                status = "Pulled to \(destination.path)"
            } catch {
                status = nil
                self.error = error.localizedDescription
            }
        }
    }

    func push() {
        guard let device = selectedDevice else { return }
        let panel = NSOpenPanel()
        panel.title = "Push to Android"
        panel.prompt = "Push"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let destination = path
        status = "Pushing \(urls.count) item\(urls.count == 1 ? "" : "s")…"
        error = nil
        Task {
            do {
                for url in urls {
                    try await ADBService.shared.push(url, toRemoteDirectory: destination, device: device)
                }
                status = "Pushed to \(destination)"
                loadPath()
            } catch {
                status = nil
                self.error = error.localizedDescription
            }
        }
    }

    private static func cacheDirectory() throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("UU Explorer/Android Browser", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

struct AndroidBrowserView: View {
    @StateObject private var browser: AndroidBrowserModel
    @Environment(\.dismiss) private var dismiss

    init(preferredSerial: String? = nil) {
        _browser = StateObject(wrappedValue: AndroidBrowserModel(preferredSerial: preferredSerial))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "candybarphone")
                    .font(.system(size: 23))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Android Devices")
                        .font(.system(size: 18, weight: .semibold))
                    Text(browser.selectedDevice.map { "\($0.model) · \($0.serial)" } ?? "USB debugging required")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let device = browser.selectedDevice {
                    Picker("Device", selection: $browser.selectedSerial) {
                        ForEach(browser.devices) { item in
                            Text(item.displayName).tag(Optional(item.serial))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                    .onChange(of: browser.selectedSerial) { _, _ in
                        browser.loadPath()
                    }
                    .disabled(device.state != "device")
                }
                Button {
                    browser.refreshDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh devices")
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)

            Divider()

            HStack(spacing: 8) {
                Button {
                    browser.up()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(browser.path == "/")
                .help("Parent folder")
                Text(browser.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer()
                Button {
                    browser.loadPath()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(browser.isLoading || browser.selectedDevice == nil)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)

            Divider()

            if browser.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Reading \(browser.path)…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = browser.error, browser.entries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Android device unavailable").fontWeight(.semibold)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
                .overlay(alignment: .bottom) {
                    if ADBService.shared.adbPath == nil {
                        Button("Locate ADB…") {
                            ADBService.shared.chooseADBPath()
                            browser.refreshDevices()
                        }
                        .padding(.bottom, 20)
                    }
                }
            } else if browser.entries.isEmpty {
                Text("This folder is empty.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $browser.selection) {
                    ForEach(browser.entries) { entry in
                        HStack(spacing: 9) {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                                .frame(width: 17)
                            Text(entry.name)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                            Spacer()
                            if let size = entry.byteSize {
                                Text(ByteFormat.string(size))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(entry.id)
                        .onTapGesture(count: 2) {
                            browser.navigate(to: entry)
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack(spacing: 8) {
                if let status = browser.status {
                    Text(status)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let error = browser.error {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                Spacer()
                Button("Open") { browser.openSelection() }
                    .disabled(browser.selection.isEmpty)
                Button("Pull Selected…") { browser.pullSelection() }
                    .disabled(browser.selection.isEmpty)
                Button("Push…") { browser.push() }
                    .disabled(browser.selectedDevice == nil)
            }
            .padding(14)
        }
        .frame(width: 820, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { browser.refreshDevices() }
    }
}
