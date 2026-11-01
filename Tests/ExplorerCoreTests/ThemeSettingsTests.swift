import XCTest
@testable import ExplorerCore

final class ThemeSettingsTests: XCTestCase {
    func testHexParsingAndRoundTrip() {
        XCTAssertEqual(ThemeColor(hex: "#4B9BFF"), ThemeColor(red: 75 / 255, green: 155 / 255, blue: 1))
        XCTAssertEqual(ThemeColor(hex: "0A84FF")?.hex, "#0A84FF")
        XCTAssertNil(ThemeColor(hex: "#XYZ123"))
        XCTAssertNil(ThemeColor(hex: "#12345"))
    }

    func testReadableForegroundChoosesContrast() {
        let light = ThemeColor(hex: "#FFFFFF")!
        let dark = ThemeColor(hex: "#111318")!
        XCTAssertEqual(light.readableForeground, .readableDark)
        XCTAssertEqual(dark.readableForeground, .readableLight)
        XCTAssertGreaterThan(light.contrastRatio(with: .readableDark), 15)
        XCTAssertGreaterThan(dark.contrastRatio(with: .white), 4)
    }

    func testPaletteRoleRoundTrip() {
        var palette = ThemePresets.standard.light
        palette.setHex("#123456", for: .folder)
        XCTAssertEqual(palette.folder, "#123456")
        XCTAssertEqual(palette.color(for: .folder)?.hex, "#123456")
        XCTAssertEqual(palette.hex(for: .accent), ThemePresets.standard.light.accent)
    }

    func testThemeSettingsCodableRoundTrip() throws {
        var settings = ThemeSettings.default
        settings.appearance = .dark
        settings.folderIconStyle = .outline
        settings.light.setHex("#ABC123", for: .background)
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ThemeSettings.self, from: encoded)
        XCTAssertEqual(decoded, settings)
    }

    func testPresetsHaveReadableFolderAndAccentColours() {
        for preset in ThemePresets.all {
            for mode in ThemeMode.allCases {
                let palette = mode == .light ? preset.light : preset.dark
                let content = palette.color(for: .content)!
                let folder = palette.color(for: .folder)!
                let accent = palette.color(for: .accent)!
                XCTAssertGreaterThanOrEqual(
                    folder.contrastRatio(with: content),
                    2.0,
                    "\(preset.name) \(mode.rawValue) folder contrast"
                )
                XCTAssertGreaterThanOrEqual(
                    accent.contrastRatio(with: content),
                    2.5,
                    "\(preset.name) \(mode.rawValue) accent contrast"
                )
            }
        }
    }

    func testThemeWarningsAreActionable() {
        var settings = ThemeSettings.default
        settings.light.folder = settings.light.content
        XCTAssertFalse(settings.warnings(for: .light).isEmpty)
        XCTAssertTrue(ThemeSettings.default.warnings(for: .light).isEmpty)
    }
}
