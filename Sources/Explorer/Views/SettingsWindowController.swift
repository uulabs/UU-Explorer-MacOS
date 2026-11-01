import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var themeStore: ThemeStore?

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(themeStore: ThemeStore) {
        self.themeStore = themeStore
    }

    func showSettings() {
        guard let themeStore else { return }

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "UU Explorer Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: SettingsView(themeStore: themeStore)
                    .environmentObject(themeStore)
            )
            if !window.setFrameUsingName("UUExplorer.SettingsWindow") {
                window.center()
            }
            window.setFrameAutosaveName("UUExplorer.SettingsWindow")
            self.window = window
        }

        showWindow(nil)
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
