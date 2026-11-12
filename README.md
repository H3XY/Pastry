# 🥐 Pastry

A small, native clipboard history app for macOS, made to work like **Win+V** on Windows.

Press **⇧⌘V** anywhere to bring up everything you've copied, search it, and paste any item back into the app you're using.

## Features

- **Pop-up history next to your cursor.** Type to search, use ↑ ↓ to move, and press ↩ to paste.
- **Quick paste:** ⌘1–⌘9 paste one of the first nine items directly.
- **Pinning:** ⌘P pins an item so it stays at the top and is never trimmed.
- **Handles text, images and screenshots, and files copied in Finder.**
- **History survives restarts.** It's saved to `~/Library/Application Support/Pastry/`.
- **Respects privacy markers.** Copies that password managers mark as concealed or transient (1Password and others) are never recorded.
- **Menu bar only:** no Dock icon. The menu has pause recording, history size (50–1000), launch at login, and a shortcut picker (⇧⌘V, ⌃⌘V, ⌥⌘V, ⇧⌘C).
- **Lightweight:** plain Swift, AppKit and SwiftUI, with no dependencies and no Xcode project.

## Install

Requires macOS 13 or later and Xcode (or the Command Line Tools).

```bash
git clone https://github.com/H3XY/Pastry.git
cd Pastry
./build.sh --install
```

This builds `Pastry.app`, copies it to `~/Applications`, and launches it. Look for the clipboard icon in your menu bar.

### Auto-paste permission

To paste straight into the app you're using, Pastry needs **Accessibility** access: System Settings → Privacy & Security → Accessibility → turn on Pastry. Without it, choosing an item only copies it to the clipboard and you press ⌘V yourself.

> The build uses an ad-hoc signature, so macOS forgets the Accessibility permission each time you rebuild. If auto-paste stops working after a rebuild, toggle Pastry off and on in that settings list.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| ⇧⌘V | Open or close Pastry (changeable from the menu bar) |
| ↑ / ↓ | Move the selection |
| ↩ | Paste the selected item |
| ⌘1 – ⌘9 | Paste item 1–9 |
| ⌘P | Pin or unpin |
| ⌘⌫ | Delete the item |
| esc | Close |

## How it works

| File | Role |
| --- | --- |
| `Sources/ClipboardMonitor.swift` | Checks `NSPasteboard.changeCount` every 0.4 s, because macOS has no clipboard-change notification |
| `Sources/ClipStore.swift` | Stores history and pins, saves it as JSON, and keeps images as PNG files |
| `Sources/HotKey.swift` | Global shortcut via Carbon `RegisterEventHotKey` (needs no permissions) |
| `Sources/PanelController.swift` | Non-activating floating panel, so the app you were typing in keeps focus, plus keyboard handling and the simulated ⌘V |
| `Sources/HistoryView.swift` | The SwiftUI list UI |
| `Sources/App.swift` | Menu bar item and settings |

## Known limitations

- Rich text is stored as plain text, so formatting is lost when pasting from history.
- ⇧⌘V overrides "Paste and Match Style" in apps that use it, such as Google Docs and Slack. Pick another shortcut from the menu if that matters to you.
