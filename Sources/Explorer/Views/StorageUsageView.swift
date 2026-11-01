import ExplorerCore
import SwiftUI

struct StorageUsageView: View {
    @ObservedObject var model: ExplorerModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ResolvedTheme { themeStore.resolved(for: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage Usage")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(model.volume?.name ?? "This Mac")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            if let volume = model.volume,
               let total = volume.totalCapacity,
               let available = volume.availableCapacity,
               total > 0 {
                VStack(alignment: .leading, spacing: 7) {
                    ProgressView(value: Double(total - available), total: Double(total))
                        .tint(theme.accent)
                    HStack {
                        Text("\(ByteFormat.string(total - available)) used")
                        Spacer()
                        Text("\(ByteFormat.string(available)) free of \(ByteFormat.string(total))")
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("Volume capacity is unavailable.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                Text("Current Folder")
                    .font(.system(size: 11.5, weight: .semibold))
                Text(model.currentURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if model.isCalculatingStorageSize {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Measuring folder…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } else if let size = model.storageFolderSize {
                    HStack(spacing: 18) {
                        metric(title: "Size", value: ByteFormat.string(size.bytes))
                        metric(title: "Files", value: "\(size.fileCount)")
                        metric(title: "Folders", value: "\(size.directoryCount)")
                    }
                    Text("Allocated: \(ByteFormat.exact(size.allocatedBytes))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Measure this folder to see its recursive size.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Button("Recalculate") { model.calculateStorageSize() }
                    .disabled(model.isCalculatingStorageSize)
                Spacer()
                Button("Done") { model.hideStorageUsage() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 350)
        .background(theme.background)
        .onAppear {
            if model.storageFolderSize == nil {
                model.calculateStorageSize()
            }
        }
        .onDisappear {
            if model.isShowingStorageUsage {
                model.hideStorageUsage()
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}
