import AppKit

/// Manual update check — the ONLY network request in the entire app, and it
/// fires exclusively when the user clicks "Check for Updates…". Nothing is
/// ever checked automatically; nothing identifies the user (a bare GET for a
/// version string). This is a privacy promise, not an implementation detail.
enum UpdateChecker {
    private static let versionURL =
        URL(string: "https://raw.githubusercontent.com/RonakToprani/aircontrol/main/VERSION")!
    private static let releasesURL =
        URL(string: "https://github.com/RonakToprani/aircontrol/releases/latest")!

    @MainActor
    static func check() {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0"
        var request = URLRequest(url: versionURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let latest = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                present(current: current, latest: ok ? latest : nil)
            }
        }.resume()
    }

    @MainActor
    private static func present(current: String, latest: String?) {
        let alert = NSAlert()
        NSApp.activate(ignoringOtherApps: true)
        guard let latest, !latest.isEmpty else {
            alert.messageText = "Couldn't check for updates"
            alert.informativeText = "The version feed wasn't reachable. Try again later, or visit the releases page."
            alert.addButton(withTitle: "Open Releases Page")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesURL)
            }
            return
        }
        if isNewer(latest, than: current) {
            alert.messageText = "Version \(latest) is available"
            alert.informativeText = "You're on \(current). The releases page has the new build and what changed."
            alert.addButton(withTitle: "Get the Update")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesURL)
            }
        } else {
            alert.messageText = "You're up to date"
            alert.informativeText = "AirControl \(current) is the latest version."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    /// Numeric dotted-version compare; unequal lengths pad with zeros.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
