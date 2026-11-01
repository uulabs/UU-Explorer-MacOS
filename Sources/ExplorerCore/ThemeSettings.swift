import Foundation

public enum ThemeAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum ThemeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        rawValue.capitalized
    }
}

public enum FolderIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case classic
    case duotone
    case outline
    case minimal
    case glossy
    case stack
    case pixel
    case bold

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .duotone: return "Duotone"
        case .outline: return "Outline"
        case .minimal: return "Flat"
        case .glossy: return "Glossy"
        case .stack: return "Stack"
        case .pixel: return "Pixel"
        case .bold: return "Bold"
        }
    }

    public var detail: String {
        switch self {
        case .classic: return "Tinted folder with a soft gradient"
        case .duotone: return "Two-tone folder with a contrasting tab"
        case .outline: return "Line-art folder outline"
        case .minimal: return "Single-colour flat folder"
        case .glossy: return "Tinted folder with a glassy highlight"
        case .stack: return "Layered folders with visible depth"
        case .pixel: return "Blocky eight-bit folder silhouette"
        case .bold: return "Heavy outline with a solid fill"
        }
    }
}

public enum ThemeColorRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case background
    case content
    case sidebar
    case toolbar
    case folder
    case accent

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .background: return "Window"
        case .content: return "Content"
        case .sidebar: return "Sidebar"
        case .toolbar: return "Toolbar"
        case .folder: return "Folders"
        case .accent: return "Accent"
        }
    }

    public var detail: String {
        switch self {
        case .background: return "Title bar and window base"
        case .content: return "Details list and gallery surface"
        case .sidebar: return "Quick Access and folder tree"
        case .toolbar: return "Top bar, search fields and status bar"
        case .folder: return "Folder icons in the tree, list and gallery"
        case .accent: return "Selection, focus rings and highlights"
        }
    }
}

public struct ThemeColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    public init?(hex rawHex: String) {
        var value = rawHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255.0,
            green: Double((number >> 8) & 0xFF) / 255.0,
            blue: Double(number & 0xFF) / 255.0
        )
    }

    public var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    public var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public func contrastRatio(with other: ThemeColor) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public func mixed(with other: ThemeColor, amount: Double) -> ThemeColor {
        let fraction = min(max(amount, 0), 1)
        return ThemeColor(
            red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction
        )
    }

    public static let white = ThemeColor(red: 1, green: 1, blue: 1)
    public static let black = ThemeColor(red: 0, green: 0, blue: 0)
    public static let readableDark = ThemeColor(red: 0.07, green: 0.08, blue: 0.10)
    public static let readableLight = ThemeColor(red: 0.97, green: 0.97, blue: 0.98)

    /// Near-white or near-black, whichever reads better on this surface.
    public var readableForeground: ThemeColor {
        contrastRatio(with: .readableLight) >= contrastRatio(with: .readableDark)
            ? .readableLight
            : .readableDark
    }

    public var prefersLightText: Bool {
        contrastRatio(with: .readableLight) >= contrastRatio(with: .readableDark)
    }
}

public struct ThemePalette: Codable, Equatable, Sendable {
    public var background: String
    public var content: String
    public var sidebar: String
    public var toolbar: String
    public var folder: String
    public var accent: String

    public init(
        background: String,
        content: String,
        sidebar: String,
        toolbar: String,
        folder: String,
        accent: String
    ) {
        self.background = background
        self.content = content
        self.sidebar = sidebar
        self.toolbar = toolbar
        self.folder = folder
        self.accent = accent
    }

    public func hex(for role: ThemeColorRole) -> String {
        switch role {
        case .background: return background
        case .content: return content
        case .sidebar: return sidebar
        case .toolbar: return toolbar
        case .folder: return folder
        case .accent: return accent
        }
    }

    public mutating func setHex(_ hex: String, for role: ThemeColorRole) {
        switch role {
        case .background: background = hex
        case .content: content = hex
        case .sidebar: sidebar = hex
        case .toolbar: toolbar = hex
        case .folder: folder = hex
        case .accent: accent = hex
        }
    }

    public func color(for role: ThemeColorRole) -> ThemeColor? {
        ThemeColor(hex: hex(for: role))
    }

    public func foreground(for role: ThemeColorRole) -> ThemeColor {
        color(for: role)?.readableForeground ?? .readableDark
    }
}

public struct ThemeSettings: Codable, Equatable, Sendable {
    public var appearance: ThemeAppearance
    public var light: ThemePalette
    public var dark: ThemePalette
    public var folderIconStyle: FolderIconStyle
    public var presetID: String

    public init(
        appearance: ThemeAppearance = .system,
        light: ThemePalette = ThemePresets.standard.light,
        dark: ThemePalette = ThemePresets.standard.dark,
        folderIconStyle: FolderIconStyle = .classic,
        presetID: String = ThemePresets.standard.id
    ) {
        self.appearance = appearance
        self.light = light
        self.dark = dark
        self.folderIconStyle = folderIconStyle
        self.presetID = presetID
    }

    public static let `default` = ThemeSettings()

    public func palette(for mode: ThemeMode) -> ThemePalette {
        mode == .light ? light : dark
    }

    public func palette(for appearance: ThemeAppearance, systemIsDark: Bool) -> ThemePalette {
        switch appearance {
        case .light: return light
        case .dark: return dark
        case .system: return systemIsDark ? dark : light
        }
    }

    public func warnings(for mode: ThemeMode) -> [String] {
        let palette = palette(for: mode)
        guard let content = palette.color(for: .content) else { return ["The palette contains an invalid colour value."] }
        var warnings: [String] = []
        if let folder = palette.color(for: .folder), folder.contrastRatio(with: content) < 2.0 {
            warnings.append("Folder colour is low-contrast against the content background.")
        }
        if let accent = palette.color(for: .accent), accent.contrastRatio(with: content) < 2.5 {
            warnings.append("Accent colour is low-contrast against the content background.")
        }
        if let sidebar = palette.color(for: .sidebar),
           let sidebarText = palette.color(for: .sidebar)?.readableForeground,
           sidebarText.contrastRatio(with: sidebar) < 3.0 {
            warnings.append("Sidebar text may be hard to read with this colour.")
        }
        return warnings
    }
}

public struct ThemePreset: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let light: ThemePalette
    public let dark: ThemePalette

    public init(id: String, name: String, light: ThemePalette, dark: ThemePalette) {
        self.id = id
        self.name = name
        self.light = light
        self.dark = dark
    }
}

public enum ThemePresets {
    public static let standard = ThemePreset(
        id: "default",
        name: "Default",
        light: ThemePalette(
            background: "#F2F2F7",
            content: "#FFFFFF",
            sidebar: "#F7F7FA",
            toolbar: "#FAFAFC",
            folder: "#4B9BFF",
            accent: "#0A84FF"
        ),
        dark: ThemePalette(
            background: "#1B1B1E",
            content: "#1E1E20",
            sidebar: "#242428",
            toolbar: "#1B1B1E",
            folder: "#5B9DFF",
            accent: "#0A84FF"
        )
    )

    public static let midnight = ThemePreset(
        id: "midnight",
        name: "Midnight",
        light: ThemePalette(
            background: "#E7EDF7",
            content: "#F8FAFF",
            sidebar: "#DCE5F4",
            toolbar: "#EDF2FB",
            folder: "#2563EB",
            accent: "#0369A1"
        ),
        dark: ThemePalette(
            background: "#070B14",
            content: "#0B1120",
            sidebar: "#0A101C",
            toolbar: "#070C16",
            folder: "#60A5FA",
            accent: "#22D3EE"
        )
    )

    public static let graphite = ThemePreset(
        id: "graphite",
        name: "Graphite",
        light: ThemePalette(
            background: "#F3F4F6",
            content: "#FFFFFF",
            sidebar: "#ECEEF2",
            toolbar: "#F6F7F9",
            folder: "#64748B",
            accent: "#0F766E"
        ),
        dark: ThemePalette(
            background: "#0B0F17",
            content: "#111827",
            sidebar: "#0E1522",
            toolbar: "#0B0F17",
            folder: "#94A3B8",
            accent: "#38BDF8"
        )
    )

    public static let nord = ThemePreset(
        id: "nord",
        name: "Nord",
        light: ThemePalette(
            background: "#ECEFF4",
            content: "#F8F9FB",
            sidebar: "#E5E9F0",
            toolbar: "#F1F4F8",
            folder: "#5E81AC",
            accent: "#4C6A8F"
        ),
        dark: ThemePalette(
            background: "#2E3440",
            content: "#272C36",
            sidebar: "#2B313C",
            toolbar: "#2E3440",
            folder: "#88C0D0",
            accent: "#A3BE8C"
        )
    )

    public static let solarized = ThemePreset(
        id: "solarized",
        name: "Solarized",
        light: ThemePalette(
            background: "#FDF6E3",
            content: "#FFFBF0",
            sidebar: "#EEE8D5",
            toolbar: "#F5EFDC",
            folder: "#268BD2",
            accent: "#A66A00"
        ),
        dark: ThemePalette(
            background: "#002B36",
            content: "#073642",
            sidebar: "#00252F",
            toolbar: "#002B36",
            folder: "#2AA198",
            accent: "#D8A21A"
        )
    )

    public static let rose = ThemePreset(
        id: "rose",
        name: "Rosé",
        light: ThemePalette(
            background: "#FAF4ED",
            content: "#FFF9F2",
            sidebar: "#F2E9E1",
            toolbar: "#F6EFE8",
            folder: "#EB6F92",
            accent: "#907AA9"
        ),
        dark: ThemePalette(
            background: "#191724",
            content: "#1F1D2E",
            sidebar: "#1A1826",
            toolbar: "#191724",
            folder: "#EBBCBA",
            accent: "#C4A7E7"
        )
    )


    public static let ocean = ThemePreset(
        id: "ocean",
        name: "Ocean",
        light: ThemePalette(
            background: "#E8F4F4",
            content: "#F7FCFC",
            sidebar: "#DFF0F0",
            toolbar: "#EDF7F7",
            folder: "#0E7490",
            accent: "#0F766E"
        ),
        dark: ThemePalette(
            background: "#041318",
            content: "#061A21",
            sidebar: "#05161C",
            toolbar: "#041318",
            folder: "#22D3EE",
            accent: "#2DD4BF"
        )
    )

    public static let forest = ThemePreset(
        id: "forest",
        name: "Forest",
        light: ThemePalette(
            background: "#EEF4EC",
            content: "#F9FCF7",
            sidebar: "#E4EDE1",
            toolbar: "#F2F7EF",
            folder: "#2F6B3C",
            accent: "#3F6212"
        ),
        dark: ThemePalette(
            background: "#0B1410",
            content: "#0F1B15",
            sidebar: "#0D1712",
            toolbar: "#0B1410",
            folder: "#86C67C",
            accent: "#A3C585"
        )
    )

    public static let ember = ThemePreset(
        id: "ember",
        name: "Ember",
        light: ThemePalette(
            background: "#F7EDE7",
            content: "#FFF8F3",
            sidebar: "#F0E1D8",
            toolbar: "#FAF1EB",
            folder: "#B45309",
            accent: "#C2410C"
        ),
        dark: ThemePalette(
            background: "#180D09",
            content: "#21130E",
            sidebar: "#1C100B",
            toolbar: "#180D09",
            folder: "#FB923C",
            accent: "#FBBF24"
        )
    )

    public static let lavender = ThemePreset(
        id: "lavender",
        name: "Lavender",
        light: ThemePalette(
            background: "#F3EFFA",
            content: "#FBF9FF",
            sidebar: "#ECE5F6",
            toolbar: "#F7F3FC",
            folder: "#7C3AED",
            accent: "#9333EA"
        ),
        dark: ThemePalette(
            background: "#100A1B",
            content: "#171024",
            sidebar: "#130C1F",
            toolbar: "#100A1B",
            folder: "#C4B5FD",
            accent: "#A78BFA"
        )
    )

    public static let all: [ThemePreset] = [
        standard,
        midnight,
        graphite,
        nord,
        solarized,
        rose,
        ocean,
        forest,
        ember,
        lavender
    ]

    public static func preset(withID id: String) -> ThemePreset? {
        all.first { $0.id == id }
    }
}
