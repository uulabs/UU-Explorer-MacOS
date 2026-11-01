import AppKit
import ExplorerCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var editingMode: ThemeMode = .light
    @State private var confirmReset = false

    private var theme: ResolvedTheme { themeStore.resolved(fromMode: editingMode) }
    private var palette: ThemePalette { themeStore.palette(for: editingMode) }
    private var warnings: [String] { themeStore.warnings(for: editingMode) }
    private var isCustom: Bool { themeStore.activePreset == nil }

    var body: some View {
        HStack(spacing: 0) {
            controls
            Divider()
            preview
        }
        .frame(width: 860, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            editingMode = colorScheme == .dark ? .dark : .light
        }
        .onChange(of: themeStore.settings.appearance) { _, appearance in
            switch appearance {
            case .light: editingMode = .light
            case .dark: editingMode = .dark
            case .system: break
            }
        }
        .confirmationDialog(
            "Reset the UU Explorer theme?",
            isPresented: $confirmReset,
            titleVisibility: .visible
        ) {
            Button("Reset Theme", role: .destructive) {
                themeStore.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All custom light and dark palette colours, folder icons and appearance choices return to the default theme.")
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Appearance & Theme")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Colours apply live. Text contrasts are selected automatically for readability.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                settingsCard("Appearance") {
                    Picker("", selection: Binding(
                        get: { themeStore.settings.appearance },
                        set: { themeStore.setAppearance($0) }
                    )) {
                        ForEach(ThemeAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("System follows the macOS appearance. Light and Dark force the whole app.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                settingsCard("Theme Presets") {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(themeStore.presets) { preset in
                            presetButton(preset)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(isCustom ? "Custom palette" : themeStore.activePreset?.name ?? "Custom palette")
                            .font(.system(size: 10.5, weight: .medium))
                        if isCustom {
                            Text("· edited manually")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                settingsCard("Palette") {
                    HStack(spacing: 3) {
                        ForEach(ThemeMode.allCases) { mode in
                            Button {
                                editingMode = mode
                            } label: {
                                Text("\(mode.title) palette")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(editingMode == mode ? Color.primary.opacity(0.13) : Color.clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 9) {
                        ForEach(ThemeColorRole.allCases) { role in
                            colorRow(role)
                        }
                    }

                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                settingsCard("Folder Icons") {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(FolderIconStyle.allCases) { style in
                            folderStyleButton(style)
                        }
                    }

                    Text("Folder icons use the folder colour from the palette being previewed. The app icon stays the dark UU Explorer folder.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("Changes save automatically.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Theme") { confirmReset = true }
                }
            }
            .padding(22)
        }
        .frame(width: 448)
    }

    private var preview: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(editingMode.title) palette · \(themeStore.settings.folderIconStyle.title) folders")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(editingMode.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.contentSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.contentField, in: Capsule())
            }
            .frame(width: 330)

            ThemePreview(theme: theme)
                .frame(width: 372, height: 426)

            VStack(alignment: .leading, spacing: 5) {
                Text("Window, content, sidebar, toolbar, folder accents and the selected folder style all update live.")
                Text("Text and selection foregrounds are derived from each surface for contrast.")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 330, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func presetButton(_ preset: ThemePreset) -> some View {
        let isActive = themeStore.settings.presetID == preset.id
        return Button {
            themeStore.applyPreset(preset)
        } label: {
            HStack(spacing: 7) {
                HStack(spacing: 1) {
                    swatch(preset.light.background)
                    swatch(preset.light.folder)
                    swatch(preset.dark.background)
                    swatch(preset.dark.folder)
                }
                .frame(width: 44, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                Text(preset.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func colorRow(_ role: ThemeColorRole) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(role.title)
                        .font(.system(size: 11, weight: .medium))
                    Text(palette.hex(for: role))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(role.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ColorPicker(
                "",
                selection: Binding(
                    get: {
                        let rgb = palette.color(for: role) ?? .readableDark
                        return rgb.color
                    },
                    set: { color in
                        guard let rgb = ThemeColor(nsColor: NSColor(color)) else { return }
                        themeStore.setColor(rgb, role: role, mode: editingMode)
                    }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 30)
            .help("Choose \(role.title.lowercased()) colour")
        }
        .frame(minHeight: 28)
    }

    private func folderStyleButton(_ style: FolderIconStyle) -> some View {
        let selected = themeStore.settings.folderIconStyle == style
        let image = FolderIconRenderer.icon(folderColor: theme.folderRGB, style: style)
        return Button {
            themeStore.setFolderIconStyle(style)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title)
                        .font(.system(size: 10.5, weight: .medium))
                    Text(style.detail)
                        .font(.system(size: 8.8))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? theme.accent.opacity(0.13) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? theme.accent.opacity(0.6) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func swatch(_ hex: String) -> some View {
        Rectangle()
            .fill(Color(nsColor: ThemeColor(hex: hex)?.nsColor ?? .gray))
    }
}

private struct ThemePreview: View {
    let theme: ResolvedTheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(theme.backgroundText.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 0) {
                    sidebar
                    content
                }
                .frame(height: 312)
                statusBar
            }
            .background(theme.content)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(theme.divider, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .padding(18)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red.opacity(0.85)).frame(width: 7, height: 7)
            Circle().fill(Color.yellow.opacity(0.85)).frame(width: 7, height: 7)
            Circle().fill(Color.green.opacity(0.85)).frame(width: 7, height: 7)
            Spacer().frame(width: 5)
            Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
            Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            Spacer().frame(width: 3)
            HStack(spacing: 3) {
                Image(systemName: "internaldrive").font(.system(size: 7))
                Text("Pictures / Travel").font(.system(size: 8))
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 6))
            }
            .foregroundStyle(theme.toolbarText.opacity(0.85))
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background(theme.field, in: RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity)
            Image(systemName: "magnifyingglass").font(.system(size: 8))
            Image(systemName: "list.bullet").font(.system(size: 8))
            Image(systemName: "square.grid.2x2.fill").font(.system(size: 8)).foregroundStyle(theme.accent)
        }
        .foregroundStyle(theme.toolbarText)
        .padding(.horizontal, 10)
        .frame(height: 35)
        .background(theme.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.toolbarDivider).frame(height: 1)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("QUICK ACCESS")
                .font(.system(size: 6.5, weight: .semibold))
                .foregroundStyle(theme.sidebarSecondary)
                .padding(.leading, 5)
                .padding(.top, 5)

            sidebarRow("Pictures", selected: true)
            sidebarRow("Camera", selected: false)
            sidebarRow("Wallpapers", selected: false)

            Rectangle().fill(theme.sidebarDivider).frame(height: 1).padding(.vertical, 4)

            Text("THIS MAC")
                .font(.system(size: 6.5, weight: .semibold))
                .foregroundStyle(theme.sidebarSecondary)
                .padding(.leading, 5)

            sidebarRow("Travel", selected: false)
            sidebarRow("Archive", selected: false)
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(width: 128)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.sidebarDivider).frame(width: 1)
        }
    }

    private func sidebarRow(_ title: String, selected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(nsImage: theme.folderIcon)
                .resizable()
                .frame(width: 11, height: 11)
            Text(title)
                .font(.system(size: 8.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.sidebarText)
        .padding(.horizontal, 4)
        .frame(height: 18)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(selected ? theme.accent.opacity(0.23) : Color.clear)
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Pictures")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.contentText)
                Spacer()
                Text("Gallery")
                    .font(.system(size: 7.5))
                    .foregroundStyle(theme.contentSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                previewItem("Sunset.jpg", selected: false, kind: .photo)
                previewItem("Coast.heic", selected: true, kind: .photo)
                previewItem("Travel", selected: false, kind: .folder)
                previewItem("Notes.md", selected: false, kind: .document)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)
        }
        .background(theme.content)
    }

    private enum PreviewKind { case photo, folder, document }

    private func previewItem(_ name: String, selected: Bool, kind: PreviewKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(theme.contentField)
                switch kind {
                case .photo:
                    RoundedRectangle(cornerRadius: 5)
                        .fill(
                            LinearGradient(
                                colors: [theme.accent.opacity(0.8), theme.folder.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "photo")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                case .folder:
                    Image(nsImage: theme.folderIcon)
                        .resizable()
                        .frame(width: 30, height: 30)
                case .document:
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.contentSecondary)
                }
            }
            .frame(height: 64)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? theme.accent : Color.clear, lineWidth: 1.5)
            )

            Text(name)
                .font(.system(size: 7.5, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(theme.contentText)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(selected ? theme.accent.opacity(0.12) : Color.clear)
        )
    }

    private var statusBar: some View {
        HStack(spacing: 5) {
            Text("12 items")
            Spacer()
            Text("1 selected · 2.4 MB")
            Rectangle().fill(theme.toolbarDivider).frame(width: 1, height: 9)
            Text("182 GB free")
        }
        .font(.system(size: 7))
        .foregroundStyle(theme.toolbarText.opacity(0.78))
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(theme.toolbar)
    }
}

private extension ThemeColor {
    init?(nsColor: NSColor) {
        guard let color = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: color.redComponent,
            green: color.greenComponent,
            blue: color.blueComponent
        )
    }
}
