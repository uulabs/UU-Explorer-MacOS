import AppKit
import Combine
import Carbon
import Darwin
import ExplorerCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var model: ExplorerModel?
    private var tabs: TabManager?
    private var menuActions: ExplorerMenuActions?
    private var titleCancellable: AnyCancellable?
    private var themeStore: ThemeStore?
    private var themeCancellable: AnyCancellable?
    private var launchAppearanceOverride: String?
    private var keyMonitor: Any?
    private var sessions: [BrowserSession] = []
    private var primarySession: BrowserSession?
    private var activeSession: BrowserSession?
    private var updateService: UpdateService?
    private var autoUpdateMenuItem: NSMenuItem?

    private var pendingOpen: (urls: [URL], reveal: Bool)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // NSWorkspace reveal requests use the Finder's make-visible Apple event.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleRevealEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kAEMiscStandards),
            andEventID: AEEventID(kAEMakeObjectsVisible)
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openExternal(urls, reveal: false)
    }

    @objc private func handleRevealEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let descriptor = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        openExternal(fileURLs(in: descriptor), reveal: true)
    }

    private func fileURLs(in descriptor: NSAppleEventDescriptor) -> [URL] {
        if descriptor.descriptorType == typeAEList {
            return (0..<descriptor.numberOfItems).flatMap { index -> [URL] in
                guard let item = descriptor.atIndex(index + 1) else { return [] }
                return fileURLs(in: item)
            }
        }
        guard let value = descriptor.coerce(toDescriptorType: typeFileURL)?.stringValue,
              let url = URL(string: value), url.isFileURL else { return [] }
        return [url]
    }

    private func openExternal(_ urls: [URL], reveal: Bool) {
        let localURLs = urls.filter(\.isFileURL)
        guard !localURLs.isEmpty else { return }
        guard let model, let window else {
            // LaunchServices can deliver the initial request before the window exists.
            pendingOpen = (localURLs, reveal)
            return
        }
        model.openExternal(localURLs, reveal: reveal)
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = LaunchOptions.parse(CommandLine.arguments)

        // Visual-verification overrides are session-only. The debug runner and
        // the installed app share the Application Support theme backup, so a
        // QA snapshot must never rewrite the user's durable theme.
        let hasEphemeralThemeOverride =
            options.themeAppearance != nil ||
            options.themePreset != nil ||
            options.folderStyle != nil
        let themeStore = ThemeStore(persistsChanges: !hasEphemeralThemeOverride)
        if let appearance = options.themeAppearance.flatMap(ThemeAppearance.init(rawValue:)) {
            themeStore.setAppearance(appearance)
        }
        self.themeStore = themeStore
        self.launchAppearanceOverride = options.appearance
        applyThemeAppearance()

        let restoreSession = options.startURL == nil && options.snapshotPath == nil
        let primary = makeSession(
            startURL: options.startURL,
            restoreSession: restoreSession,
            frameName: "UUExplorer.MainWindow"
        )
        primarySession = primary
        window = primary.window
        model = primary.activePane.model
        tabs = primary.activePane.tabs
        let model = primary.activePane.model

        let actions = ExplorerMenuActions(model: primary.activePane.model, tabs: primary.activePane.tabs)
        actions.newWindow = { [weak self] in self?.openNewWindow() }
        actions.moveTabToNewWindow = { [weak self] in self?.moveActiveTabToNewWindow() }
        actions.splitViewToggle = { [weak self] in self?.toggleSplitView() }
        actions.splitViewIsActive = { [weak self] in self?.activeSession?.isSplitView ?? false }
        menuActions = actions
        buildMainMenu(actions: actions)
        let updateService = UpdateService(window: window)
        self.updateService = updateService
        syncAutoUpdateMenu()
        SettingsWindowController.shared.configure(themeStore: themeStore)

        themeCancellable = themeStore.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyThemeChrome() }

        activate(primary)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        primary.activePane.tabs.restoreOnLaunchIfNeeded()
        installKeyMonitor()

        if let pending = pendingOpen {
            pendingOpen = nil
            openExternal(pending.urls, reveal: pending.reveal)
        }

        if options.startURL == nil,
           options.snapshotPath == nil {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.updateService?.checkAutomatically()
            }
        }

        if let presetID = options.themePreset,
           let preset = ThemePresets.preset(withID: presetID) {
            themeStore.applyPreset(preset)
        }
        if let viewMode = options.viewMode.flatMap(ViewMode.init(rawValue:)) {
            model.setViewMode(viewMode)
        }
        if let folderStyle = options.folderStyle.flatMap(FolderIconStyle.init(rawValue:)) {
            themeStore.setFolderIconStyle(folderStyle)
        }
        if options.showSettings {
            SettingsWindowController.shared.showSettings()
        }

        if let snapshotPath = options.snapshotPath {
            Task { @MainActor [weak self] in
                await self?.writeSnapshot(to: snapshotPath, options: options)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        for session in sessions {
            session.primary.tabs.captureActiveAndSave()
            session.secondary?.tabs.captureActiveAndSave()
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    @discardableResult
    private func makeSession(
        startURL: URL?,
        restoreSession: Bool,
        frameName: String? = nil,
        detachedState: ExplorerTabState? = nil
    ) -> BrowserSession {
        guard let themeStore else {
            fatalError("Theme store must exist before creating a browser session")
        }

        let primary = BrowserPane(startURL: startURL, restoreSession: restoreSession)
        let session = BrowserSession(primary: primary)

        let window = ExplorerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configureWindowActions(window, session: session)
        window.title = "UU Explorer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 960, height: 560)
        window.backgroundColor = .windowBackgroundColor
        session.window = window
        window.contentView = NSHostingView(
            rootView: WindowRootView(session: session)
                .environmentObject(themeStore)
        )
        primary.tabs.onCloseWindow = { [weak window] in
            window?.performClose(nil)
        }
        window.onBecomeKey = { [weak self, weak session] in
            guard let self, let session else { return }
            self.activate(session)
        }

        if let frameName {
            if !window.setFrameUsingName(frameName) {
                window.center()
            }
            window.setFrameAutosaveName(frameName)
        } else if let keyWindow = NSApp.keyWindow {
            let origin = NSPoint(
                x: keyWindow.frame.minX + 28,
                y: keyWindow.frame.maxY - window.frame.height - 28
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        sessions.append(session)
        if let detachedState {
            primary.tabs.adoptDetachedState(detachedState)
        }
        session.onActivePaneChange = { [weak self, weak session] in
            guard let self, let session else { return }
            self.activate(session)
        }
        return session
    }

    private func configureWindowActions(_ window: ExplorerWindow, session: BrowserSession) {
        window.navigateBack = { [weak session] in
            guard let model = session?.activePane.model, model.nameEditor == nil else { return }
            model.goBack()
        }
        window.navigateForward = { [weak session] in
            guard let model = session?.activePane.model, model.nameEditor == nil else { return }
            model.goForward()
        }
        window.copyFiles = { [weak session] in session?.activePane.model.copySelectionToPasteboard() }
        window.cutFiles = { [weak session] in session?.activePane.model.copySelectionToPasteboard(cut: true) }
        window.pasteFiles = { [weak session] in session?.activePane.model.pasteFiles() }
        window.canCopyFiles = { [weak session] in
            !(session?.activePane.model.selection.isEmpty ?? true)
        }
        window.canPasteFiles = { [weak session] in
            session?.activePane.model.canPaste ?? false
        }
        window.undoFiles = { [weak session] in session?.activePane.model.undoFileOperation() }
        window.redoFiles = { [weak session] in session?.activePane.model.redoFileOperation() }
        window.canUndoFiles = { [weak session] in
            session?.activePane.model.canUndoFileOperation ?? false
        }
        window.canRedoFiles = { [weak session] in
            session?.activePane.model.canRedoFileOperation ?? false
        }
        window.undoTitle = { [weak session] in session?.activePane.model.undoTitle }
        window.redoTitle = { [weak session] in session?.activePane.model.redoTitle }
    }

    private func activate(_ session: BrowserSession) {
        activeSession = session
        window = session.window
        model = session.activePane.model
        tabs = session.activePane.tabs
        menuActions?.update(model: session.activePane.model, tabs: session.activePane.tabs)
        observeWindowTitle(model: session.activePane.model)
        applyWindowTheme()
    }

    private func toggleSplitView() {
        guard let activeSession else { return }
        activeSession.toggleSplitView()
        activate(activeSession)
    }

    private func openNewWindow() {
        let session = makeSession(
            startURL: model?.currentURL,
            restoreSession: false
        )
        activate(session)
        session.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func moveActiveTabToNewWindow() {
        guard let tabs, let model else { return }
        guard let detached = tabs.takeActiveTabForDetachedWindow() else {
            model.showStatus("Open another tab before moving a tab to a new window.", kind: .error)
            return
        }
        let session = makeSession(
            startURL: URL(fileURLWithPath: detached.state.path),
            restoreSession: false,
            detachedState: detached.state
        )
        activate(session)
        session.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  let model = self.model,
                  NSApp.keyWindow === window,
                  window.attachedSheet == nil else { return event }
            if event.keyCode == 40, event.modifierFlags.contains(.command) {
                model.toggleCommandPalette()
                return nil
            }
            if window.firstResponder is NSTextView {
                return event
            }
            if let responder = window.firstResponder,
               responder is NSControl,
               !(responder is NSTableView) {
                return event
            }
            if event.keyCode == 48, event.modifierFlags.contains(.control) {
                if event.modifierFlags.contains(.shift) {
                    self.tabs?.selectPreviousTab()
                } else {
                    self.tabs?.selectNextTab()
                }
                return nil
            }

            if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                return event
            }

            if event.keyCode == 49 { // Space: Quick Look
                guard !model.selectedItems.isEmpty else { return event }
                model.quickLookSelection()
                return nil
            }

            guard model.viewMode == .gallery else { return event }
            switch event.keyCode {
            case 123, 126: // Left / Up
                model.moveGallerySelection(by: -1)
                return nil
            case 124, 125: // Right / Down
                model.moveGallerySelection(by: 1)
                return nil
            case 36, 76: // Return / keypad Enter
                model.openSelectedItems()
                return nil
            default:
                return event
            }
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func checkForUpdates(_ sender: Any?) {
        updateService?.checkForUpdates(manual: true)
    }

    @objc private func toggleAutoUpdateChecks(_ sender: Any?) {
        guard let updateService else { return }
        updateService.autoChecksEnabled.toggle()
        syncAutoUpdateMenu()
    }

    private func syncAutoUpdateMenu() {
        autoUpdateMenuItem?.state = (updateService?.autoChecksEnabled ?? false) ? .on : .off
    }

    private func applyThemeChrome() {
        applyThemeAppearance()
        applyWindowTheme()
    }

    private func applyThemeAppearance() {
        if let override = launchAppearanceOverride {
            switch override {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: NSApp.appearance = nil
            }
            return
        }
        guard let themeStore else { return }
        switch themeStore.settings.appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func applyWindowTheme() {
        guard let window, let themeStore else { return }
        let settings = themeStore.settings
        window.backgroundColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let palette = settings.palette(for: isDark ? .dark : .light)
            return palette.color(for: .background)?.nsColor ?? .windowBackgroundColor
        }
    }

    private func observeWindowTitle(model: ExplorerModel) {
        titleCancellable = model.$currentURL
            .combineLatest(model.$currentFolderName)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self, let window = self.window else { return }
                let (url, folderName) = value
                window.title = folderName.isEmpty ? "UU Explorer" : folderName
                window.representedURL = url
            }
    }

    // MARK: - Snapshot (used for visual verification of the app)

    private func writeSnapshot(to path: String, options: LaunchOptions) async {
        guard let model, let window else { return }

        try? await Task.sleep(nanoseconds: 150_000_000)
        let deadline = Date().addingTimeInterval(20)
        while model.isLoading && Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        if let selectName = options.selectName {
            if let item = model.items.first(where: {
                $0.name == selectName || $0.url.lastPathComponent == selectName
            }) {
                model.selection = [item.id]
            } else if let firstFile = model.items.first(where: { !$0.isDirectory }) {
                model.selection = [firstFile.id]
            }
        }

        if options.selectAll {
            model.selection = Set(model.displayedItems.map(\.id))
        }

        if options.editPath {
            model.beginPathEditing()
            if let draft = options.pathDraft {
                model.updatePathDraft(draft)
            }
        }

        if options.showNewFolder {
            model.beginNewFolder()
        }

        NSApp.activate(ignoringOtherApps: true)
        if options.showSettings {
            SettingsWindowController.shared.window?.makeKeyAndOrderFront(nil)
        } else {
            window.makeKey()
        }
        try? await Task.sleep(nanoseconds: 700_000_000)

        let captureWindow = (options.showSettings ? SettingsWindowController.shared.window : nil)
            ?? window.attachedSheet
            ?? window
        captureWindow.displayIfNeeded()

        guard let targetView = captureWindow.contentView?.superview ?? captureWindow.contentView,
              let rep = targetView.bitmapImageRepForCachingDisplay(in: targetView.bounds) else {
            fputs("Snapshot failed: no view to capture\n", stderr)
            exitSnapshot()
        }
        targetView.cacheDisplay(in: targetView.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            fputs("Snapshot failed: PNG encoding failed\n", stderr)
            exitSnapshot()
        }

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try data.write(to: url)
            print("SNAPSHOT \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        } catch {
            fputs("Snapshot failed: \(error.localizedDescription)\n", stderr)
        }
        exitSnapshot()
    }

    private func exitSnapshot() -> Never {
        if let window, let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        fflush(stdout)
        exit(0)
    }

    // MARK: - Main menu

    private func buildMainMenu(actions: ExplorerMenuActions) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "UU Explorer")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        add(appMenu, "About UU Explorer", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        add(appMenu, "Check for Updates…", #selector(checkForUpdates(_:)), target: self)
        let autoUpdate = add(
            appMenu,
            "Automatically Check for Updates",
            #selector(toggleAutoUpdateChecks(_:)),
            target: self
        )
        autoUpdateMenuItem = autoUpdate
        appMenu.addItem(.separator())
        add(appMenu, "Settings…", #selector(showSettings(_:)), target: self, key: ",", modifiers: [.command])
        add(appMenu, "Hide UU Explorer", #selector(NSApplication.hide(_:)), key: "h")
        add(
            appMenu,
            "Hide Others",
            #selector(NSApplication.hideOtherApplications(_:)),
            key: "h",
            modifiers: [.command, .option]
        )
        add(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        appMenu.addItem(.separator())
        add(appMenu, "Quit UU Explorer", #selector(NSApplication.terminate(_:)), key: "q")

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        add(fileMenu, "New Window", #selector(ExplorerMenuActions.newWindow(_:)), target: actions, key: "n")
        add(fileMenu, "Move Tab to New Window", #selector(ExplorerMenuActions.moveTabToNewWindow(_:)), target: actions, key: "n", modifiers: [.command, .control])
        add(fileMenu, "New Tab", #selector(ExplorerMenuActions.newTab(_:)), target: actions, key: "t")
        add(fileMenu, "Reopen Closed Tab", #selector(ExplorerMenuActions.reopenClosedTab(_:)), target: actions, key: "t", modifiers: [.command, .shift])
        fileMenu.addItem(.separator())
        add(
            fileMenu,
            "New Folder",
            #selector(ExplorerMenuActions.newFolder(_:)),
            target: actions,
            key: "N",
            modifiers: [.command, .shift]
        )
        add(
            fileMenu,
            "New File",
            #selector(ExplorerMenuActions.newFile(_:)),
            target: actions,
            key: "n",
            modifiers: [.command, .option]
        )
        fileMenu.addItem(.separator())
        add(fileMenu, "Open", #selector(ExplorerMenuActions.open(_:)), target: actions, key: "o")
        add(
            fileMenu,
            "Rename…",
            #selector(ExplorerMenuActions.rename(_:)),
            target: actions,
            key: String(UnicodeScalar(NSF2FunctionKey)!),
            modifiers: []
        )
        add(
            fileMenu,
            "Batch Rename…",
            #selector(ExplorerMenuActions.batchRename(_:)),
            target: actions,
            key: "r",
            modifiers: [.command, .option]
        )
        add(
            fileMenu,
            "Move to Trash",
            #selector(ExplorerMenuActions.moveToTrash(_:)),
            target: actions,
            key: "\u{8}",
            modifiers: [.command]
        )
        fileMenu.addItem(.separator())
        add(
            fileMenu,
            "Copy Path",
            #selector(ExplorerMenuActions.copyPath(_:)),
            target: actions,
            key: "c",
            modifiers: [.command, .option]
        )
        add(
            fileMenu,
            "Show in Finder",
            #selector(ExplorerMenuActions.revealInFinder(_:)),
            target: actions,
            key: "f",
            modifiers: [.command, .shift]
        )
        add(
            fileMenu,
            "Open in Terminal",
            #selector(ExplorerMenuActions.openCurrentInTerminal(_:)),
            target: actions
        )
        add(
            fileMenu,
            "Save Search",
            #selector(ExplorerMenuActions.saveSearch(_:)),
            target: actions
        )
        add(
            fileMenu,
            "Pin Current Folder to Favourites",
            #selector(ExplorerMenuActions.toggleCurrentFavorite(_:)),
            target: actions
        )
        fileMenu.addItem(.separator())
        add(fileMenu, "Properties…", #selector(ExplorerMenuActions.properties(_:)), target: actions, key: "i")
        fileMenu.addItem(.separator())
        add(fileMenu, "Close Tab", #selector(ExplorerMenuActions.closeTab(_:)), target: actions, key: "w")
        add(fileMenu, "Close Window", #selector(ExplorerMenuActions.closeWindow(_:)), target: actions, key: "w", modifiers: [.command, .shift])

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        add(editMenu, "Undo", NSSelectorFromString("undo:"), key: "z")
        let redo = add(editMenu, "Redo", NSSelectorFromString("redo:"), key: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        add(editMenu, "Cut", NSSelectorFromString("cut:"), key: "x")
        add(editMenu, "Copy", NSSelectorFromString("copy:"), key: "c")
        add(editMenu, "Paste", NSSelectorFromString("paste:"), key: "v")
        editMenu.addItem(.separator())
        add(editMenu, "Select All", NSSelectorFromString("selectAll:"), key: "a")

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        add(viewMenu, "Details", #selector(ExplorerMenuActions.showDetails(_:)), target: actions, key: "1")
        add(viewMenu, "Gallery", #selector(ExplorerMenuActions.showGallery(_:)), target: actions, key: "2")
        add(viewMenu, "Split View", #selector(ExplorerMenuActions.toggleSplitView(_:)), target: actions, key: "\\")
        viewMenu.addItem(.separator())
        add(viewMenu, "Quick Look", #selector(ExplorerMenuActions.quickLook(_:)), target: actions)
        add(
            viewMenu,
            "Larger Thumbnails",
            #selector(ExplorerMenuActions.largerThumbnails(_:)),
            target: actions,
            key: "+"
        )
        add(
            viewMenu,
            "Smaller Thumbnails",
            #selector(ExplorerMenuActions.smallerThumbnails(_:)),
            target: actions,
            key: "-"
        )
        viewMenu.addItem(.separator())

        let sortItem = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "Sort By")
        sortItem.submenu = sortMenu
        viewMenu.addItem(sortItem)
        add(sortMenu, "Name", #selector(ExplorerMenuActions.sortByName(_:)), target: actions)
        add(sortMenu, "Date Modified", #selector(ExplorerMenuActions.sortByDate(_:)), target: actions)
        add(sortMenu, "Type", #selector(ExplorerMenuActions.sortByType(_:)), target: actions)
        add(sortMenu, "Size", #selector(ExplorerMenuActions.sortBySize(_:)), target: actions)

        add(
            viewMenu,
            "Show Hidden Files",
            #selector(ExplorerMenuActions.toggleHiddenFiles(_:)),
            target: actions,
            key: ".",
            modifiers: [.command, .shift]
        )
        add(viewMenu, "Refresh", #selector(ExplorerMenuActions.refresh(_:)), target: actions, key: "r")
        viewMenu.addItem(.separator())
        add(
            viewMenu,
            "Show Preview Pane",
            #selector(ExplorerMenuActions.togglePreviewPane(_:)),
            target: actions
        )
        add(
            viewMenu,
            "Show Sidebar",
            #selector(ExplorerMenuActions.toggleSidebar(_:)),
            target: actions,
            key: "s",
            modifiers: [.control, .command]
        )
        viewMenu.addItem(.separator())
        add(
            viewMenu,
            "Enter Full Screen",
            #selector(NSWindow.toggleFullScreen(_:)),
            key: "f",
            modifiers: [.control, .command]
        )

        let goMenuItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")
        goMenuItem.submenu = goMenu
        mainMenu.addItem(goMenuItem)

        add(goMenu, "Back", #selector(ExplorerMenuActions.goBack(_:)), target: actions, key: "[")
        add(goMenu, "Forward", #selector(ExplorerMenuActions.goForward(_:)), target: actions, key: "]")
        add(
            goMenu,
            "Enclosing Folder",
            #selector(ExplorerMenuActions.goUp(_:)),
            target: actions,
            key: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifiers: [.command]
        )
        goMenu.addItem(.separator())
        add(goMenu, "Go to Folder…", #selector(ExplorerMenuActions.goToFolder(_:)), target: actions, key: "l")
        goMenu.addItem(.separator())
        add(
            goMenu,
            "Home",
            #selector(ExplorerMenuActions.goHome(_:)),
            target: actions,
            key: "h",
            modifiers: [.command, .shift]
        )
        add(
            goMenu,
            "Desktop",
            #selector(ExplorerMenuActions.goDesktop(_:)),
            target: actions,
            key: "d",
            modifiers: [.command, .shift]
        )
        add(
            goMenu,
            "Documents",
            #selector(ExplorerMenuActions.goDocuments(_:)),
            target: actions,
            key: "o",
            modifiers: [.command, .shift]
        )
        add(
            goMenu,
            "Downloads",
            #selector(ExplorerMenuActions.goDownloads(_:)),
            target: actions,
            key: "l",
            modifiers: [.command, .option]
        )
        add(
            goMenu,
            "Applications",
            #selector(ExplorerMenuActions.goApplications(_:)),
            target: actions,
            key: "a",
            modifiers: [.command, .shift]
        )

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        add(windowMenu, "Show Next Tab", #selector(ExplorerMenuActions.nextTab(_:)), target: actions, key: "\t", modifiers: [.control])
        add(windowMenu, "Show Previous Tab", #selector(ExplorerMenuActions.previousTab(_:)), target: actions, key: "\t", modifiers: [.control, .shift])
        windowMenu.addItem(.separator())
        add(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
        add(windowMenu, "Zoom", #selector(NSWindow.performZoom(_:)))
        windowMenu.addItem(.separator())
        add(windowMenu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @discardableResult
    private func add(
        _ menu: NSMenu,
        _ title: String,
        _ action: Selector,
        target: AnyObject? = nil,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        menu.addItem(item)
        return item
    }
}
