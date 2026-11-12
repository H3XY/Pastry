<img src="Resources/AppIcon-1024.png" width="128" alt="Pastry icon: a pasty">

# Pastry

[![Download for macOS](https://img.shields.io/github/v/release/H3XY/Pastry?label=Download%20for%20macOS&logo=apple&style=for-the-badge&color=E59A35)](https://github.com/H3XY/Pastry/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/H3XY/Pastry/total?style=for-the-badge&color=4A6FD8)](https://github.com/H3XY/Pastry/releases)

A small, native clipboard history app for macOS, made to work like **Win+V** on Windows.

Press **⇧⌘V** anywhere to bring up everything you've copied, search it, and paste any item back into the app you're using.

## Features

- **Pop-up history next to your cursor.** Type to search, use ↑ ↓ to move, and press ↩ to paste.
- **Quick paste:** ⌘1–⌘9 paste one of the first nine items directly.
- **Pinning:** ⌘P pins an item so it stays at the top and is never trimmed.
- **Handles text, images and screenshots, and files copied in Finder.** Formatted text keeps its formatting (bold, links, fonts); press ⇧↩ to paste it as plain text instead.
- **History survives restarts.** It's saved to `~/Library/Application Support/Pastry/`.
- **Respects privacy markers.** Copies that password managers mark as concealed or transient (1Password and others) are never recorded.
- **Menu bar only:** no Dock icon. The menu has pause recording, history size (50–1000), launch at login, and a shortcut picker: ⇧⌘V, ⌃⌘V, ⌥⌘V, ⇧⌘C, or record your own.
- **Update check:** once a day Pastry asks GitHub whether a newer release exists and offers to open the download page. You can also use **Check for Updates…** in the menu.
- **Lightweight:** plain Swift, AppKit and SwiftUI, with no dependencies and no Xcode project.

## Install

### Homebrew

```bash
brew tap h3xy/tap
brew trust h3xy/tap
brew install --cask pastry
```

Update with `brew upgrade --cask pastry`.

### Download

1. Get **Pastry-vX.Y.Z.zip** from the [latest release](https://github.com/H3XY/Pastry/releases/latest) and unzip it.
2. Drag **Pastry.app** into your Applications folder and open it.
3. Allow **Accessibility** when asked, so Pastry can paste for you.

Releases are signed with Developer ID and notarized by Apple, so they open without warnings.

It runs on macOS 13 or later, on Apple Silicon and Intel Macs.

### Build from source

Requires macOS 13 or later and Xcode (or the Command Line Tools).

```bash
git clone https://github.com/H3XY/Pastry.git
cd Pastry
./build.sh --install
```

This builds `Pastry.app`, copies it to `/Applications` (or `~/Applications` if you can't write there), and launches it. Look for the pasty in your menu bar.

### Auto-paste permission

To paste straight into the app you're using, Pastry needs **Accessibility** access: System Settings → Privacy & Security → Accessibility → turn on Pastry. Without it, choosing an item only copies it to the clipboard and you press ⌘V yourself.

> `build.sh` signs the app with your Apple Development (or Developer ID) certificate if you have one, so the permission survives rebuilds. Without a certificate it falls back to an ad-hoc signature, which changes on every build: if auto-paste stops working after a rebuild, toggle Pastry off and on in that settings list.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| ⇧⌘V | Open or close Pastry (changeable from the menu bar) |
| ↑ / ↓ | Move the selection |
| ↩ | Paste the selected item |
| ⇧↩ | Paste it as plain text (no formatting) |
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
| `Sources/MenuBarIcon.swift` | Draws the one-color pasty in the menu bar |
| `Sources/ShortcutRecorder.swift` | The "Record Custom Shortcut…" window |
| `Sources/UpdateChecker.swift` | Daily check of GitHub for a newer release |
| `Tests/main.swift` | Tests for history, pinning, formatting, search, versions and shortcuts (run `./test.sh`) |
| `tools/make-icon.swift` | Draws the pasty app icon into `Resources/AppIcon.icns` (run `xcrun swift tools/make-icon.swift`) |

## Contributing

- `main` is the released code and `dev` is where work comes together.
- Do work on a feature branch, open a pull request into `dev`, and once `dev` is ready, open a pull request from `dev` into `main`.
- The **Build** workflow compiles the app and runs the tests (`./test.sh`) on every pull request and on every push to `dev` and `main`.
- **Releasing:** bump `CFBundleShortVersionString` in `Info.plist` through the usual PRs, then on an up-to-date `main` run `./release.sh v1.2.3`. It builds a universal app, signs it with Developer ID, has Apple notarize it, then tags the commit, publishes the GitHub Release, and updates the Homebrew cask in [H3XY/homebrew-tap](https://github.com/H3XY/homebrew-tap). The setup it needs is listed at the top of `release.sh`.

## Known limitations

- ⇧⌘V overrides "Paste and Match Style" in apps that use it, such as Google Docs and Slack. Pick another shortcut from the menu, or record your own, if that matters to you.

## License

[MIT](LICENSE) © 2026 Vivek Reddy
