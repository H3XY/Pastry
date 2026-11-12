import AppKit

/// A small window that waits for the next key combination and offers it as the new shortcut.
@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var monitor: Any?
    private var label: NSTextField?
    private var onFinish: ((HotkeyPreset?) -> Void)?

    /// `onFinish` gets the new shortcut, or nil if the user cancelled.
    func start(onFinish: @escaping (HotkeyPreset?) -> Void) {
        self.onFinish = onFinish

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 130),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Record Shortcut"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let title = NSTextField(labelWithString: "Press the shortcut you want to use")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let shown = NSTextField(labelWithString: HotkeyPreset.current.label)
        shown.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        let hint = NSTextField(labelWithString: "Include ⌘, ⌃ or ⌥.  Esc cancels.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, shown, hint])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }

        label = shown
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = Int(event.keyCode)
            let chars = event.charactersIgnoringModifiers ?? ""
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handleKey(code: code, characters: chars, flags: flags) }
            return nil
        }
    }

    private func handleKey(code: Int, characters: String, flags: NSEvent.ModifierFlags) {
        var mods = HotkeyPreset.Mods()
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }

        if code == 53 && mods.isEmpty { finish(nil); return } // esc
        guard HotkeyPreset.isAllowed(mods) else {
            label?.stringValue = "Add ⌘, ⌃ or ⌥"
            NSSound.beep()
            return
        }
        let key = HotkeyPreset.keyName(keyCode: code, characters: characters)
        finish(HotkeyPreset(id: "custom", label: HotkeyPreset.label(mods, key: key),
                            keyCode: UInt32(code), modifiers: HotkeyPreset.carbonModifiers(mods)))
    }

    func windowWillClose(_ notification: Notification) { finish(nil) }

    private func finish(_ result: HotkeyPreset?) {
        guard let onFinish else { return }
        self.onFinish = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        window?.delegate = nil
        window?.close()
        window = nil
        onFinish(result)
    }
}
