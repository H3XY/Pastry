import AppKit

/// Offers to move Pastry into the Applications folder when it's opened from somewhere else
/// (usually Downloads). Replaces an older copy there, so it doubles as the update step.
@MainActor
enum AppMover {
    /// True for apps inside /Applications or ~/Applications (including subfolders).
    nonisolated static func isInApplications(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let p = (path as NSString).standardizingPath
        return p.hasPrefix("/Applications/") || p.hasPrefix(home + "/Applications/")
    }

    /// Call first thing at launch. Returns true if Pastry is relaunching from Applications
    /// (the caller should then stop setting up).
    static func moveIfNeeded() -> Bool {
        let running = Bundle.main.bundleURL
        guard running.pathExtension == "app" else { return false }
        let original = untranslocatedURL(running) ?? running
        guard !isInApplications(original.path) else { return false }
        guard !UserDefaults.standard.bool(forKey: "dontAskToMove") else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Pastry to your Applications folder?"
        alert.informativeText = "Pastry is running from \(original.deletingLastPathComponent().lastPathComponent). "
            + "Keeping it in Applications means it's always where you expect and can start when you log in."
            + (FileManager.default.fileExists(atPath: destination().path) ? " The older Pastry there will be replaced." : "")
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "dontAskToMove") }
        guard answer == .alertFirstButtonReturn else { return false }

        do {
            try move(from: running, original: original)
            return true
        } catch {
            let failed = NSAlert()
            failed.messageText = "Couldn't move Pastry"
            failed.informativeText = "\(error.localizedDescription)\n\nYou can drag Pastry into Applications yourself."
            failed.runModal()
            return false
        }
    }

    private static func destination() -> URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let dir = FileManager.default.isWritableFile(atPath: system.path)
            ? system
            : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications", isDirectory: true)
        return dir.appendingPathComponent("Pastry.app", isDirectory: true)
    }

    private static func move(from running: URL, original: URL) throws {
        let fm = FileManager.default
        let dest = destination()
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Quit any other Pastry (e.g. an older version already in Applications) before replacing it.
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app.processIdentifier != me {
            app.terminate()
        }
        if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }

        // Copy from where we're actually running (a translocated copy is byte-identical), then
        // drop the quarantine flag: the user already chose to open this download.
        try fm.copyItem(at: running, to: dest)
        removeQuarantine(dest)

        // Put the downloaded copy in the Trash rather than deleting it outright.
        try? fm.trashItem(at: original, resultingItemURL: nil)

        // Relaunch from Applications once this process has exited.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", dest.path]
        try relaunch.run()
        NSApp.terminate(nil)
    }

    private static func removeQuarantine(_ url: URL) {
        let attr = "com.apple.quarantine"
        let all = [url] + ((FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
            .allObjects as? [URL]) ?? [])
        for item in all { removexattr(item.path, attr, XATTR_NOFOLLOW) }
    }

    /// Downloaded apps first run from a hidden read-only copy ("App Translocation").
    /// Security.framework can tell us where the real file is; it's looked up at runtime
    /// because the function isn't in the public headers.
    private static func untranslocatedURL(_ url: URL) -> URL? {
        typealias IsTranslocated = @convention(c) (CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Bool
        typealias OriginalPath = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        guard let lib = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY) else { return nil }
        defer { dlclose(lib) }
        guard let isSym = dlsym(lib, "SecTranslocateIsTranslocatedURL"),
              let origSym = dlsym(lib, "SecTranslocateCreateOriginalPathForURL") else { return nil }
        let isTranslocated = unsafeBitCast(isSym, to: IsTranslocated.self)
        let originalPath = unsafeBitCast(origSym, to: OriginalPath.self)
        var translocated = false
        guard isTranslocated(url as CFURL, &translocated, nil), translocated,
              let original = originalPath(url as CFURL, nil) else { return nil }
        return original.takeRetainedValue() as URL
    }
}
