import AppKit
import ExplorerCore
import SwiftUI

struct NetworkShareWizardView: View {
    @ObservedObject var model: ExplorerModel
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var protocolChoice: NetworkProtocol = .smb
    @State private var address = ""
    @State private var displayName = ""
    @State private var autoConnect = true
    @State private var connectNow = true
    @State private var launchAtLogin = LoginItemController.isEnabled
    @State private var error: String?
    @FocusState private var addressFocused: Bool

    private var fullAddress: String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.contains("://") ? trimmed : "\(protocolChoice.rawValue)://\(trimmed)"
    }

    private var parsed: NetworkLocation? {
        try? NetworkLocation.parse(address: fullAddress, name: displayName, autoConnect: autoConnect)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(22)
        .frame(width: 560, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                addressFocused = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 25))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Network Share")
                    .font(.system(size: 19, weight: .semibold))
                Text(stepTitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            addressStep
        case 1:
            optionsStep
        default:
            reviewStep
        }
    }

    private var addressStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to a server")
                .font(.system(size: 13, weight: .medium))
            Picker("Protocol", selection: $protocolChoice) {
                ForEach(NetworkProtocol.allCases, id: \.self) { networkProtocol in
                    Text(networkProtocol.title).tag(networkProtocol)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: protocolChoice) { _, _ in
                error = nil
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Server or share")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("server.local/Share", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($addressFocused)
                    .onSubmit { advance() }
                Text("For \(protocolChoice.title), enter the server name and optional share path.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }

            Text("macOS handles authentication. Choose “Remember this password” in the system prompt to store credentials in your login keychain.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reconnect options")
                .font(.system(size: 13, weight: .medium))
            TextField("Display name (optional)", text: $displayName)
                .textFieldStyle(.roundedBorder)
            Toggle("Reconnect at app launch", isOn: $autoConnect)
            Toggle("Connect immediately after saving", isOn: $connectNow)
            Toggle("Launch UU Explorer at login", isOn: $launchAtLogin)
            Text("Launch at Login lets macOS start UU Explorer after restart so saved shares can reconnect without opening the app manually.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let parsed {
                Label("Will mount \(parsed.url?.absoluteString ?? fullAddress)", systemImage: "checkmark.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to add")
                .font(.system(size: 13, weight: .medium))
            if let parsed {
                VStack(alignment: .leading, spacing: 9) {
                    reviewRow("Name", parsed.name)
                    reviewRow("Address", parsed.url?.absoluteString ?? fullAddress)
                    reviewRow("Protocol", parsed.protocolName.title)
                    reviewRow("Reconnect at launch", autoConnect ? "Yes" : "No")
                    reviewRow("Connect now", connectNow ? "Yes" : "No")
                    reviewRow("Launch at Login", launchAtLogin ? "Yes" : "No")
                }
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            }
            Text("The share is mounted by macOS. UU Explorer stores only its address and reconnect preference; passwords remain in the system keychain.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if step > 0 {
                Button("Back") {
                    error = nil
                    step -= 1
                }
            }
            Button(step == 2 ? "Add Share" : "Continue") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "1 of 3 · Server"
        case 1: return "2 of 3 · Options"
        default: return "3 of 3 · Review"
        }
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.system(size: 11.5))
    }

    private func advance() {
        error = nil
        switch step {
        case 0:
            guard !fullAddress.isEmpty else {
                error = "Enter a server address."
                return
            }
            guard parsed != nil else {
                error = "Use a valid SMB, AFP, or NFS server and share path."
                return
            }
            step = 1
        case 1:
            step = 2
        default:
            finish()
        }
    }

    private func finish() {
        guard parsed != nil else {
            error = "The network address is invalid."
            return
        }
        let saved = model.addNetworkLocation(
            address: fullAddress,
            name: displayName,
            autoConnect: autoConnect
        )
        guard let saved else {
            error = "That network location is already saved, or it could not be added."
            return
        }
        if launchAtLogin != LoginItemController.isEnabled {
            do {
                try LoginItemController.setEnabled(launchAtLogin)
            } catch {
                model.showStatus("Couldn’t update Launch at Login: \(error.localizedDescription)", kind: .error)
            }
        }
        if connectNow {
            model.connectNetworkLocation(saved)
        }
        dismiss()
    }
}
