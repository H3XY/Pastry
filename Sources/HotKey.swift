import Carbon
import Foundation

struct HotkeyPreset {
    let id: String
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotkeyPreset] = [
        HotkeyPreset(id: "cmdShiftV", label: "⇧⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
        HotkeyPreset(id: "ctrlCmdV", label: "⌃⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)),
        HotkeyPreset(id: "optCmdV", label: "⌥⌘V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)),
        HotkeyPreset(id: "cmdShiftC", label: "⇧⌘C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey)),
    ]

    /// The shortcut recorded with "Record Custom Shortcut…", if any.
    static var custom: HotkeyPreset? {
        let d = UserDefaults.standard
        guard let label = d.string(forKey: "customHotkeyLabel") else { return nil }
        return HotkeyPreset(id: "custom", label: label,
                            keyCode: UInt32(d.integer(forKey: "customHotkeyCode")),
                            modifiers: UInt32(d.integer(forKey: "customHotkeyMods")))
    }

    static func saveCustom(_ p: HotkeyPreset) {
        let d = UserDefaults.standard
        d.set(p.label, forKey: "customHotkeyLabel")
        d.set(Int(p.keyCode), forKey: "customHotkeyCode")
        d.set(Int(p.modifiers), forKey: "customHotkeyMods")
        d.set("custom", forKey: "hotkey")
    }

    static var current: HotkeyPreset {
        let id = UserDefaults.standard.string(forKey: "hotkey") ?? "cmdShiftV"
        if id == "custom", let custom { return custom }
        return all.first { $0.id == id } ?? all[0]
    }

    // MARK: Turning a key press into a shortcut

    struct Mods: OptionSet {
        let rawValue: Int
        static let control = Mods(rawValue: 1), option = Mods(rawValue: 2)
        static let shift = Mods(rawValue: 4), command = Mods(rawValue: 8)
    }

    static func carbonModifiers(_ m: Mods) -> UInt32 {
        var c = 0
        if m.contains(.command) { c |= cmdKey }
        if m.contains(.option) { c |= optionKey }
        if m.contains(.control) { c |= controlKey }
        if m.contains(.shift) { c |= shiftKey }
        return UInt32(c)
    }

    /// Modifier symbols in Apple's standard order, then the key: "⌃⌥⇧⌘K".
    static func label(_ m: Mods, key: String) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "") + key
    }

    /// A global shortcut needs ⌘, ⌃ or ⌥; ⇧ alone would hijack normal typing.
    static func isAllowed(_ m: Mods) -> Bool {
        !m.intersection([.command, .control, .option]).isEmpty
    }

    /// Readable name for keys whose character isn't printable.
    static func keyName(keyCode: Int, characters: String) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return special[keyCode] ?? characters.uppercased()
    }
}

/// System-wide hotkey via Carbon. Needs no Accessibility permission.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    @discardableResult
    func register(_ preset: HotkeyPreset) -> Bool {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: 1) // 'CLIP'
        let status = RegisterEventHotKey(preset.keyCode, preset.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }
}
