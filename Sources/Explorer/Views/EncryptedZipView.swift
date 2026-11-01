import SwiftUI

struct EncryptedZipView: View {
    @ObservedObject var model: ExplorerModel
    let request: EncryptedZipRequest
    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !password.isEmpty && password == confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Encrypted ZIP")
                .font(.system(size: 17, weight: .semibold))
            Text("“\(request.source.lastPathComponent)” will be saved as “\(request.target.lastPathComponent)”.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Verify password", text: $confirmation)
                .textFieldStyle(.roundedBorder)

            if !password.isEmpty, !confirmation.isEmpty, password != confirmation {
                Text("Passwords do not match.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
            }

            Text("Uses classic ZIP encryption (ZipCrypto). Use a strong passphrase; the password is not stored.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") { model.encryptedZip = nil }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 420)
        .interactiveDismissDisabled()
    }

    private func create() {
        guard canCreate else {
            errorMessage = "Enter and verify the password."
            return
        }
        model.createEncryptedZip(password: password, request: request)
    }
}
