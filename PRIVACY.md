# Pastry Privacy Policy

_Last updated: November 12, 2026_

Pastry is a clipboard history app for macOS. It is built so that **what you copy never leaves your Mac**.

## What Pastry stores

- **Your clipboard history:** text (with its formatting), images, and references to files you copy. It is saved only on your Mac, in Pastry's own folder: `~/Library/Containers/com.h3xy.pastry` for the App Store version, or `~/Library/Application Support/Pastry` for the version from GitHub or Homebrew.
- **Your settings:** your shortcut, history size, and similar preferences, saved on your Mac.

You can delete any item, or clear your whole history, at any time from Pastry's menu. Deleting Pastry and its folder removes everything.

## What Pastry does not do

- It does not send your clipboard history, or anything else you copy, to the developer or anyone else.
- It has no accounts, analytics, advertising, or tracking.
- It does not record copies that password managers mark as private.

## Network access

The **App Store version** makes no network connections.

The **GitHub and Homebrew version** contacts GitHub once a day to check for a newer release of Pastry. That request contains no information about you or your clipboard, only a generic "Pastry" app name. You can see the code that does this in `Sources/UpdateChecker.swift`.

## Permissions

Pastry asks for **Accessibility** access so it can paste the item you pick into the app you're using. It uses this only to press ⌘V for you, and only when you choose an item.

## Contact

Questions about privacy? Open an issue at [github.com/H3XY/Pastry/issues](https://github.com/H3XY/Pastry/issues).
