import AppKit

MainActor.assumeIsolated {
    // Only our outgoing "Show in Finder" commands bypass the global UU Explorer viewer.
    UserDefaults.standard.set("com.apple.finder", forKey: "NSFileViewer")
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.delegate = appDelegate
    application.setActivationPolicy(.regular)
    application.run()
}
