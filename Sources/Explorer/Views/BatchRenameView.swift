import ExplorerCore
import SwiftUI

struct BatchRenameView: View {
    @ObservedObject var model: ExplorerModel
    let session: BatchRenameSession
    @State private var options = BatchRenameOptions()

    private var directoryPaths: Set<String> {
        Set(session.items.filter(\.isDirectory).map(\.url.path))
    }

    private var previews: [BatchRenamePreview] {
        BatchRenamePlanner.preview(
            items: session.items.map { BatchRenameItem(url: $0.url, isDirectory: $0.isDirectory) },
            options: options
        )
    }

    private var changed: [BatchRenamePreview] {
        previews.filter(\.hasChange)
    }

    private var hasErrors: Bool {
        previews.contains { $0.error != nil }
    }

    private var firstError: String? {
        previews.first(where: { $0.error != nil })?.error
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Batch Rename")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text("\(session.items.count) selected")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Picker("Mode", selection: $options.mode) {
                ForEach(BatchRenameMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch options.mode {
            case .findReplace:
                HStack(spacing: 8) {
                    TextField("Find", text: $options.find)
                    TextField("Replace with", text: $options.replace)
                }
                .textFieldStyle(.roundedBorder)
                Toggle("Match case", isOn: $options.caseSensitive)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
            case .addText:
                HStack(spacing: 8) {
                    TextField("Prefix", text: $options.prefix)
                    TextField("Suffix", text: $options.suffix)
                }
                .textFieldStyle(.roundedBorder)
                Text("Prefix and suffix are added around the name, before the extension.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            case .number:
                HStack(spacing: 8) {
                    TextField("Base name", text: $options.numberBase)
                        .textFieldStyle(.roundedBorder)
                    TextField("Start", value: $options.numberStart, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Stepper("Digits: \(options.numberPadding)", value: $options.numberPadding, in: 1...8)
                        .font(.system(size: 11))
                }
                Text("Files keep their extensions. Numbers follow the current sort order.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer()
                    Text("\(changed.count) will be renamed")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(previews.prefix(300))) { preview in
                            previewRow(preview)
                            if preview.id != previews.prefix(300).last?.id {
                                Divider().opacity(0.45)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            }

            if previews.count > 300 {
                Text("Showing the first 300 names of \(previews.count).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let firstError {
                Text(firstError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Extensions are preserved. Existing and duplicate names block the rename.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancelBatchRename() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { model.applyBatchRename(previews) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(changed.isEmpty || hasErrors)
            }
        }
        .padding(20)
        .frame(width: 720, height: 590)
        .interactiveDismissDisabled()
    }

    private func previewRow(_ preview: BatchRenamePreview) -> some View {
        HStack(spacing: 9) {
            Image(systemName: directoryPaths.contains(preview.sourceURL.path) ? "folder" : "doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(preview.oldName)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                if preview.hasChange {
                    Text("→ \(preview.newName)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(preview.error == nil ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let error = preview.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            } else if !preview.hasChange {
                Text("Unchanged")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
