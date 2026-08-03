import AppKit
import ApplicationServices
import CoreGraphics

/// M4 pulled forward: turn a fired swipe into a real Space switch by posting
/// the default Mission Control shortcuts ⌃← / ⌃→. Requires Accessibility
/// trust (the signing identity keeps the grant across rebuilds).
enum SpaceSwitcher {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt once if not yet trusted.
    @discardableResult
    static func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// direction: −1 = Space to the left (⌃←), +1 = Space to the right (⌃→).
    /// Posts an explicit Control down/up around the arrow — Mission Control
    /// ignores a bare flagged arrow on some systems.
    ///
    /// `warpTo` (CG coords): with "Displays have separate Spaces", macOS
    /// targets the display under the REAL cursor — warp it to the AirControl
    /// pointer first so the switch happens where the hand is, then restore.
    static func post(direction: Int, warpTo point: CGPoint? = nil) {
        guard isTrusted else { return }
        if let p = point {
            let original = CGEvent(source: nil)?.location
            CGWarpMouseCursorPosition(p)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                postKeys(direction: direction)
                if let o = original {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        CGWarpMouseCursorPosition(o)
                    }
                }
            }
            return
        }
        postKeys(direction: direction)
    }

    private static func postKeys(direction: Int) {
        let arrow: CGKeyCode = direction < 0 ? 123 : 124
        let control: CGKeyCode = 59 // kVK_Control
        let source = CGEventSource(stateID: .hidSystemState)
        func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: code, keyDown: down) else { return }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        // Real arrow keys carry fn + numeric-pad flags; Mission Control's
        // hotkey matcher requires them, or the event falls through to the
        // focused app (audible as the "unhandled key" beep).
        let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        key(control, down: true, flags: .maskControl)
        key(arrow, down: true, flags: arrowFlags)
        key(arrow, down: false, flags: arrowFlags)
        key(control, down: false, flags: [])
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
