import AppKit

/// Checks GitHub for a newer Pastry release: automatically once a day, or on demand from the menu.
@MainActor
final class UpdateChecker {
    static let releasesAPI = URL(string: "https://api.github.com/repos/H3XY/Pastry/releases/latest")!

    struct Release { let version: String; let url: URL }

    /// Set once a newer release is found, so the menu can show it.
    private(set) var available: Release?

    private let defaults: UserDefaults
    private var checking = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// True when `candidate` (e.g. "v1.2.0" or "1.2") is a later version than `current`.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let trimmed = v.hasPrefix("v") || v.hasPrefix("V") ? String(v.dropFirst()) : v
            return trimmed.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Runs on launch; only hits the network if a day has passed since the last check.
    func checkIfDue() {
        let last = defaults.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - last > 24 * 60 * 60 else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pastry", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            let release: Release? = {
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
                return Release(version: tag, url: page)
            }()
            let failed = error != nil || release == nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(release, failed: failed, userInitiated: userInitiated) }
            }
        }.resume()
    }

    private func finish(_ release: Release?, failed: Bool, userInitiated: Bool) {
        checking = false
        if failed {
            if userInitiated { alert("Couldn't check for updates", "Make sure you're online and try again.") }
            return
        }
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        guard let release, Self.isNewer(release.version, than: Self.currentVersion) else {
            available = nil
            if userInitiated { alert("You're up to date", "Pastry \(Self.currentVersion) is the latest version.") }
            return
        }
        available = release
        // Don't nag about a version the user chose to skip, unless they asked.
        if !userInitiated && defaults.string(forKey: "skippedVersion") == release.version { return }
        offer(release)
    }

    func offer(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Pastry \(release.version) is available"
        a.informativeText = "You have \(Self.currentVersion). Download the new version from GitHub, unzip it and open it, then choose Move to Applications to replace this one."
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip This Version")
        switch a.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(release.url)
        case .alertThirdButtonReturn: defaults.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
