import AppKit
import SwiftUI

/// A borderless-looking panel that can take keyboard focus without activating the app,
/// so the app you were typing in stays frontmost and receives the paste.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: KeyPanel
    private let store: ClipStore
    private let monitor: ClipboardMonitor
    private let model = PanelModel()
    private var keyMonitor: Any?

    init(store: ClipStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
                         styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                         backing: .buffered, defer: false)
        super.init()

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self

        let view = HistoryView(store: store, model: model,
                               onPaste: { [weak self] in self?.paste($0) },
                               onOpenAccessibility: { [weak self] in self?.openAccessibility() })
        panel.contentView = NSHostingView(rootView: view)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        model.query = ""
        model.selection = 0
        model.axTrusted = AXIsProcessTrusted()
        positionNearMouse()
        panel.makeKeyAndOrderFront(nil)
        model.focusToken += 1
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) ?? event }
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return }
        let size = panel.frame.size
        var x = mouse.x - size.width / 2
        var y = mouse.y - size.height - 12
        if y < vf.minY { y = mouse.y + 12 }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let items = model.visible(store)
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        switch event.keyCode {
        case 53: // esc
            hide(); return nil
        case 125: // down
            if !items.isEmpty { model.selection = min(model.selection + 1, items.count - 1) }
            return nil
        case 126: // up
            model.selection = max(model.selection - 1, 0)
            return nil
        case 36, 76: // return / enter
            if items.indices.contains(model.selection) { paste(items[model.selection]) }
            return nil
        default: break
        }

        guard flags == .command else { return event }
        let sel = items.indices.contains(model.selection) ? items[model.selection] : nil

        if event.keyCode == 51, let sel { // ⌘⌫
            store.remove(sel.id)
            model.selection = min(model.selection, max(model.visible(store).count - 1, 0))
            return nil
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p":
            if let sel { store.togglePin(sel.id) }
            return nil
        case "w":
            hide(); return nil
        case let c? where c.count == 1 && ("1"..."9").contains(c):
            let i = Int(c)! - 1
            if items.indices.contains(i) { paste(items[i]) }
            return nil
        default:
            return event
        }
    }

    func paste(_ item: ClipItem) {
        store.write(item)
        monitor.markOwnWrite()
        if !item.pinned { store.bumpToTop(item.id) }
        hide()
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Self.sendCommandV() }
    }

    private static func sendCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    func openAccessibility() {
        hide()
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
