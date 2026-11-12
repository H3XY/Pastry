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

    static var current: HotkeyPreset {
        let id = UserDefaults.standard.string(forKey: "hotkey") ?? "cmdShiftV"
        return all.first { $0.id == id } ?? all[0]
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
