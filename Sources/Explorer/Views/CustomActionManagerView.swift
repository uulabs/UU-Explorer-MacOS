import SwiftUI

struct CustomActionManagerView: View {
    @ObservedObject var model: ExplorerModel
    @Environment(\.dismiss) private var dismiss
    @State private var editingAction: CustomAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom Actions")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Shell commands receive the selection as arguments and in UU_SELECTED_PATHS.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Action") {
                    editingAction = CustomAction(name: "New Action", command: "echo \"$UU_SELECTED_COUNT items\"")
                }
                .buttonStyle(.borderedProminent)
            }

            if model.customActions.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "terminal")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No custom actions yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add a command to run against the current selection or folder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.customActions) { action in
                        HStack(spacing: 10) {
                            Image(systemName: "terminal")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name.isEmpty ? "Untitled Action" : action.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text("\(action.scope.title) · \(action.runInTerminal ? "Terminal" : "Background")")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { action.isEnabled },
                                set: { enabled in
                                    var copy = action
                                    copy.isEnabled = enabled
                                    model.upsertCustomAction(copy)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            Button("Edit") { editingAction = action }
                            Button {
                                model.deleteCustomAction(action)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .help("Delete action")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Text("Commands run with your user permissions. Only add scripts you trust.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 700, height: 480)
        .sheet(item: $editingAction) { action in
            CustomActionEditorView(action: action) { edited in
                model.upsertCustomAction(edited)
                editingAction = nil
            } onCancel: {
                editingAction = nil
            }
        }
    }
}

private struct CustomActionEditorView: View {
    @State private var draft: CustomAction
    @State private var error: String?
    let onSave: (CustomAction) -> Void
    let onCancel: () -> Void

    init(action: CustomAction, onSave: @escaping (CustomAction) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: action)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.name.isEmpty ? "Edit Action" : draft.name)
                .font(.system(size: 17, weight: .semibold))
            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 5) {
                Text("Command").font(.system(size: 11, weight: .medium))
                TextEditor(text: $draft.command)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 110)
                    .padding(6)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            }
            Picker("Scope", selection: $draft.scope) {
                ForEach(CustomActionScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Run in Terminal (keeps output visible)", isOn: $draft.runInTerminal)
            Toggle("Enabled", isOn: $draft.isEnabled)
            if let error {
                Text(error).font(.system(size: 10.5)).foregroundStyle(.red)
            }
            Text("The selection is available as \"$@\", $UU_SELECTED_PATHS (newline-separated), $UU_FIRST_PATH, and $UU_CURRENT_DIR.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                        error = "Enter a name."
                        return
                    }
                    guard !draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        error = "Enter a command."
                        return
                    }
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 470)
    }
}
