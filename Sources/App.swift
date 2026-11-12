import AppKit
import ServiceManagement

@main
@MainActor
enum PastryMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var store: ClipStore!
    private var monitor: ClipboardMonitor!
    private var panel: PanelController!
    private var hotKey: HotKey!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let updater = UpdateChecker()
    private let recorder = ShortcutRecorder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if !APPSTORE // the App Store installs into Applications itself
        // Opened from Downloads (or anywhere else)? Offer to move to Applications and relaunch there.
        if AppMover.moveIfNeeded() { return }
        #endif

        store = ClipStore()
        monitor = ClipboardMonitor(store: store)
        monitor.start()
        panel = PanelController(store: store, monitor: monitor)

        hotKey = HotKey { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        hotKey.register(HotkeyPreset.current)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.make()
        menu.delegate = self
        statusItem.menu = menu

        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            if !AXIsProcessTrusted() { panel.openAccessibility() }
        }
        syncLaunchAtLogin()
        #if !APPSTORE // the App Store handles updates
        updater.checkIfDue()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) { store?.saveNow() }

    /// Launch at login is on by default. The choice is remembered separately from macOS's login-item
    /// record, so after Pastry moves or is replaced by an update it re-registers at its new location.
    private var wantsLaunchAtLogin: Bool {
        get { UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "launchAtLogin") }
    }

    private func syncLaunchAtLogin() {
        let service = SMAppService.mainApp
        if wantsLaunchAtLogin {
            if service.status != .enabled { try? service.register() }
        } else if service.status == .enabled {
            try? service.unregister()
        }
    }

    // Rebuilt every time it opens so check marks are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        #if !APPSTORE
        if let release = updater.available {
            menu.addItem(NSMenuItem(title: "Update Available: \(release.version)…",
                                    action: #selector(showUpdate), keyEquivalent: ""))
            menu.addItem(.separator())
        }
        #endif

        let show = NSMenuItem(title: "Show Clipboard   \(HotkeyPreset.current.label)",
                              action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(show)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.state = monitor.paused ? .on : .off
        menu.addItem(pause)

        let hk = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        let hkMenu = NSMenu()
        for p in HotkeyPreset.all + [HotkeyPreset.custom].compactMap({ $0 }) {
            let i = NSMenuItem(title: p.label, action: #selector(pickHotkey(_:)), keyEquivalent: "")
            i.representedObject = p.id
            i.state = p.id == HotkeyPreset.current.id ? .on : .off
            hkMenu.addItem(i)
        }
        hkMenu.addItem(.separator())
        hkMenu.addItem(NSMenuItem(title: "Record Custom Shortcut…", action: #selector(recordHotkey), keyEquivalent: ""))
        hk.submenu = hkMenu
        menu.addItem(hk)

        let keep = NSMenuItem(title: "History Size", action: nil, keyEquivalent: "")
        let keepMenu = NSMenu()
        for n in [50, 100, 200, 500, 1000] {
            let i = NSMenuItem(title: "\(n) items", action: #selector(pickSize(_:)), keyEquivalent: "")
            i.tag = n
            i.state = n == store.maxItems ? .on : .off
            keepMenu.addItem(i)
        }
        keep.submenu = keepMenu
        menu.addItem(keep)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if !AXIsProcessTrusted() {
            menu.addItem(NSMenuItem(title: "Enable Auto-Paste (Accessibility)…",
                                    action: #selector(openAX), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Clear History (keeps pinned)", action: #selector(clear), keyEquivalent: ""))
        menu.addItem(.separator())
        #if !APPSTORE
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: ""))
        #endif
        let version = NSMenuItem(title: "Pastry \(UpdateChecker.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(NSMenuItem(title: "Quit Pastry", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        hkMenu.items.forEach { $0.target = self }
        keepMenu.items.forEach { $0.target = self }
    }

    @objc private func showPanel() {
        // Let the menu finish closing first, otherwise the panel loses focus immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.panel.show() }
    }
    @objc private func togglePause() { monitor.paused.toggle() }
    @objc private func pickHotkey(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let preset = (HotkeyPreset.all + [HotkeyPreset.custom].compactMap({ $0 }))
                .first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(id, forKey: "hotkey")
        if !hotKey.register(preset) { warnTaken(preset) }
    }
    @objc private func recordHotkey() {
        hotKey.unregister() // so pressing the current shortcut gets recorded instead of opening Pastry
        recorder.start { [weak self] new in
            guard let self else { return }
            guard let new else { self.hotKey.register(HotkeyPreset.current); return }
            if self.hotKey.register(new) {
                HotkeyPreset.saveCustom(new)
            } else {
                self.hotKey.register(HotkeyPreset.current)
                self.warnTaken(new)
            }
        }
    }
    private func warnTaken(_ preset: HotkeyPreset) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(preset.label) is already used by another app."
        alert.informativeText = "Pick a different shortcut."
        alert.runModal()
    }
    @objc private func checkUpdates() { updater.check(userInitiated: true) }
    @objc private func showUpdate() { if let r = updater.available { updater.offer(r) } }
    @objc private func pickSize(_ sender: NSMenuItem) { store.maxItems = sender.tag }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                wantsLaunchAtLogin = false
            } else {
                try SMAppService.mainApp.register()
                wantsLaunchAtLogin = true
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
    @objc private func openAX() { panel.openAccessibility() }
    @objc private func clear() { store.clearUnpinned() }
    @objc private func quit() { NSApp.terminate(nil) }
}
