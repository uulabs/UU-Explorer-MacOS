import AppKit
import ExplorerCore
import SwiftUI

@MainActor
final class ThemeStore: ObservableObject {
    static let storageKey = "UUExplorer.theme.v1"

    @Published private(set) var settings: ThemeSettings
    private let defaults: UserDefaults
    private let storageURL: URL?
    private let persistsChanges: Bool

    init(
        defaults: UserDefaults = .standard,
        storageURL: URL? = nil,
        persistsChanges: Bool = true
    ) {
        self.defaults = defaults
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.persistsChanges = persistsChanges

        if let url = self.storageURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(ThemeSettings.self, from: data) {
            settings = decoded
        } else if let data = defaults.data(forKey: Self.storageKey),
                  let decoded = try? JSONDecoder().decode(ThemeSettings.self, from: data) {
            settings = decoded
            persist()
        } else {
            settings = .default
        }
    }

    private static func defaultStorageURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["UU_EXPLORER_THEME_FILE"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return support
            .appendingPathComponent("UU Explorer", isDirectory: true)
            .appendingPathComponent("theme.json")
    }

    var presets: [ThemePreset] { ThemePresets.all }

    var activePreset: ThemePreset? {
        ThemePresets.preset(withID: settings.presetID)
    }

    func resolved(for colorScheme: ColorScheme) -> ResolvedTheme {
        let mode: ThemeMode
        switch settings.appearance {
        case .light: mode = .light
        case .dark: mode = .dark
        case .system: mode = colorScheme == .dark ? .dark : .light
        }
        return ResolvedTheme(settings: settings, mode: mode)
    }

    func resolved(for appearance: NSAppearance) -> ResolvedTheme {
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return resolved(for: dark ? .dark : .light)
    }

    func resolved(fromMode mode: ThemeMode) -> ResolvedTheme {
        ResolvedTheme(settings: settings, mode: mode)
    }

    func setAppearance(_ appearance: ThemeAppearance) {
        guard settings.appearance != appearance else { return }
        settings.appearance = appearance
        persist()
    }

    func setColor(_ color: ThemeColor, role: ThemeColorRole, mode: ThemeMode) {
        var palette = settings.palette(for: mode)
        palette.setHex(color.hex, for: role)
        if mode == .light {
            settings.light = palette
        } else {
            settings.dark = palette
        }
        settings.presetID = "custom"
        persist()
    }

    func setFolderIconStyle(_ style: FolderIconStyle) {
        guard settings.folderIconStyle != style else { return }
        settings.folderIconStyle = style
        persist()
    }

    func applyPreset(_ preset: ThemePreset) {
        settings.light = preset.light
        settings.dark = preset.dark
        settings.presetID = preset.id
        persist()
    }

    func reset() {
        settings = .default
        persist()
    }

    func palette(for mode: ThemeMode) -> ThemePalette {
        settings.palette(for: mode)
    }

    func warnings(for mode: ThemeMode) -> [String] {
        settings.warnings(for: mode)
    }

    private func persist() {
        guard persistsChanges else { return }
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)

        guard let storageURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: .atomic)
        } catch {
            NSLog("UU Explorer: couldn’t save theme backup: \(error.localizedDescription)")
        }
    }
}

/// A resolved palette for one of the two modes. AppKit and SwiftUI colours are
/// derived here so every surface gets a readable foreground automatically.
struct ResolvedTheme: Equatable {
    let mode: ThemeMode
    let palette: ThemePalette
    let folderIconStyle: FolderIconStyle

    init(settings: ThemeSettings, mode: ThemeMode) {
        self.mode = mode
        self.palette = settings.palette(for: mode)
        self.folderIconStyle = settings.folderIconStyle
    }

    var backgroundRGB: ThemeColor { palette.color(for: .background) ?? .white }
    var contentRGB: ThemeColor { palette.color(for: .content) ?? .white }
    var sidebarRGB: ThemeColor { palette.color(for: .sidebar) ?? .white }
    var toolbarRGB: ThemeColor { palette.color(for: .toolbar) ?? .white }
    var folderRGB: ThemeColor { palette.color(for: .folder) ?? .readableDark }
    var accentRGB: ThemeColor { palette.color(for: .accent) ?? .readableDark }

    var backgroundNS: NSColor { backgroundRGB.nsColor }
    var contentNS: NSColor { contentRGB.nsColor }
    var sidebarNS: NSColor { sidebarRGB.nsColor }
    var toolbarNS: NSColor { toolbarRGB.nsColor }
    var folderNS: NSColor { folderRGB.nsColor }
    var accentNS: NSColor { accentRGB.nsColor }

    var background: Color { backgroundNS.color }
    var content: Color { contentNS.color }
    var sidebar: Color { sidebarNS.color }
    var toolbar: Color { toolbarNS.color }
    var folder: Color { folderNS.color }
    var accent: Color { accentNS.color }

    var contentTextNS: NSColor { contentRGB.readableForeground.nsColor }
    var contentText: Color { contentTextNS.color }
    var contentSecondaryNS: NSColor { contentTextNS.withAlphaComponent(0.64) }
    var contentSecondary: Color { contentSecondaryNS.color }

    var backgroundTextNS: NSColor { backgroundRGB.readableForeground.nsColor }
    var backgroundText: Color { backgroundTextNS.color }
    var sidebarTextNS: NSColor { sidebarRGB.readableForeground.nsColor }
    var sidebarText: Color { sidebarTextNS.color }
    var sidebarSecondary: Color { sidebarTextNS.withAlphaComponent(0.6).color }
    var toolbarTextNS: NSColor { toolbarRGB.readableForeground.nsColor }
    var toolbarText: Color { toolbarTextNS.color }
    var toolbarSecondary: Color { toolbarTextNS.withAlphaComponent(0.62).color }
    var accentTextNS: NSColor { accentRGB.readableForeground.nsColor }
    var accentText: Color { accentTextNS.color }

    var dividerNS: NSColor { contentTextNS.withAlphaComponent(0.16) }
    var divider: Color { dividerNS.color }
    var sidebarDivider: Color { sidebarTextNS.withAlphaComponent(0.14).color }
    var toolbarDivider: Color { toolbarTextNS.withAlphaComponent(0.16).color }

    var fieldNS: NSColor { toolbarRGB.mixed(with: toolbarRGB.readableForeground, amount: 0.065).nsColor }
    var field: Color { fieldNS.color }
    var contentFieldNS: NSColor { contentRGB.mixed(with: contentRGB.readableForeground, amount: 0.055).nsColor }
    var contentField: Color { contentFieldNS.color }

    var hoverNS: NSColor { contentRGB.readableForeground.nsColor.withAlphaComponent(0.065) }
    var hover: Color { hoverNS.color }
    var sidebarHover: Color { sidebarRGB.readableForeground.nsColor.withAlphaComponent(0.06).color }

    var isContentDark: Bool { contentRGB.prefersLightText }
    var isSidebarDark: Bool { sidebarRGB.prefersLightText }
    var isToolbarDark: Bool { toolbarRGB.prefersLightText }

    var folderIcon: NSImage {
        MainActor.assumeIsolated {
            FolderIconRenderer.icon(folderColor: folderRGB, style: folderIconStyle)
        }
    }

    /// A stable value for AppKit view diffing.
    var signature: String {
        [
            mode.rawValue,
            folderIconStyle.rawValue,
            palette.background,
            palette.content,
            palette.sidebar,
            palette.toolbar,
            palette.folder,
            palette.accent
        ].joined(separator: "|")
    }
}

extension ThemeColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var color: Color {
        Color(nsColor: nsColor)
    }
}

extension NSColor {
    var color: Color {
        Color(nsColor: self)
    }
}
