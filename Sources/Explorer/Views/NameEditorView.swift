import AppKit
import SwiftUI

struct NameEditorView: View {
    @ObservedObject var model: ExplorerModel
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if let editor = model.nameEditor {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(editor.title)
                            .font(.system(size: 15, weight: .semibold))
                        Text(subtitle(for: editor))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    TextField("Name", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .focused($isFocused)
                        .onSubmit {
                            model.submitNameEditor(text)
                        }

                    if let error = editor.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                    }

                    HStack {
                        Spacer()
                        Button("Cancel") {
                            model.cancelNameEditor()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button(editor.confirmLabel) {
                            model.submitNameEditor(text)
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(20)
                .frame(width: 430)
                .task(id: editor.id) {
                    text = editor.text
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    isFocused = true
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
    }

    private func subtitle(for editor: NameEditor) -> String {
        switch editor.mode {
        case .rename(let source):
            let parent = source.deletingLastPathComponent()
            let parentName = parent.path == "/"
                ? (FileSystemServiceVolumeName.name(for: parent) ?? "Macintosh HD")
                : parent.lastPathComponent
            return "Rename “\(source.lastPathComponent)” in “\(parentName)”."
        case .newFolder, .newFile:
            return "Create in “\(model.currentFolderName)”."
        }
    }
}

private enum FileSystemServiceVolumeName {
    static func name(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
    }
}
