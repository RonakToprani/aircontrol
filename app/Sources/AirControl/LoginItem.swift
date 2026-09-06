import ServiceManagement

/// Start-at-login, backed directly by the system — SMAppService IS the store,
/// so there's no Config field to keep in sync. Registration can fail (an
/// unbundled dev binary, a system hiccup); callers read `enabled` back to see
/// what actually stuck rather than trusting the set.
enum LoginItem {
    static var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("AirControl: login-item \(newValue ? "register" : "unregister") failed: \(error)")
            }
        }
    }
}
