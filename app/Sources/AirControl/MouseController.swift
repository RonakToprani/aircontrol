import AppKit
import QuartzCore

// Private CoreGraphics/SkyLight: lets a BACKGROUND app hide the cursor
// globally. Without the connection property, CGDisplayHideCursor only works
// while the calling app is frontmost — and AirControl lives in the menu bar.
private typealias CGSConnectionID = UInt32
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSSetConnectionProperty") @discardableResult
private func CGSSetConnectionProperty(_ cid: CGSConnectionID, _ target: CGSConnectionID,
                                      _ key: CFString, _ value: CFTypeRef) -> CGError

/// Mouse mode: drives the REAL macOS cursor from the eased AirControl pointer.
/// Pinch is the left button — engage = down, hold = drag, release = up — and
/// successive pinches in place escalate the click count, so double-click
/// (open) and triple-click (select paragraph) work like a physical mouse.
/// Events post to the HID tap, landing in whatever app is under the cursor;
/// the overlay windows are click-through, so they never swallow one.
/// Posting requires the same Accessibility trust as Space switching.
final class MouseController {
    private(set) var buttonDown = false
    /// Click-vs-drag slop: while the button is down, the cursor stays PINNED
    /// at the pinch-down point until the hand clearly escapes this radius —
    /// pinch jitter can never smear a click into a tiny drag or text-select.
    var dragSlopPx: CGFloat = 14
    /// Deferred mouse-down: a closing fist passes THROUGH the pinch shape
    /// (thumb and index tips converge), so the down waits this long — a pinch
    /// that becomes a fist is cancelled before any event posts, a held pinch
    /// commits after the delay, and a quick tap clicks in full on release.
    var downDelay: CFTimeInterval = 0.12
    private var pendingSince: CFTimeInterval?
    private var pendingPos = CGPoint.zero
    private(set) var dragging = false
    private var downPos = CGPoint.zero
    private var clickCount: Int64 = 1
    private var lastClickTime: CFTimeInterval = -1e9
    private var lastClickPos = CGPoint.zero
    private var lastMoved: CGPoint?
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Multi-click only counts when the next pinch lands about here.
    private let multiClickRadius: CGFloat = 12

    func move(to p: CGPoint) {
        if pendingSince != nil { return } // pinch forming: cursor holds still
        if buttonDown {
            if !dragging {
                guard hypot(p.x - downPos.x, p.y - downPos.y) > dragSlopPx else { return }
                dragging = true
            }
            lastMoved = p
            post(.leftMouseDragged, at: p)
            return
        }
        // A real mouse only reports when it moves; identical positions every
        // render frame are noise (and wake up event taps for nothing).
        if let last = lastMoved,
           abs(p.x - last.x) < 0.5, abs(p.y - last.y) < 0.5 { return }
        lastMoved = p
        post(.mouseMoved, at: p)
    }

    func pinchDown(at p: CGPoint, now: CFTimeInterval,
                   openQuery: Bool = false, textQuery: Bool = false) {
        guard !buttonDown, pendingSince == nil else { return }
        pendingSince = now
        pendingPos = p
        if now - lastClickTime < NSEvent.doubleClickInterval,
           hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < multiClickRadius {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now
        lastClickPos = p
        // Ask "what's under the pinch?" NOW, off the render loop — the answer
        // is back long before the pinch releases, and a stale generation (a
        // new pinch started) is discarded.
        openable = false
        textTarget = false
        openQueryGen += 1
        if openQuery || textQuery {
            let gen = openQueryGen
            axQueue.async { [weak self] in
                let hit = Self.classify(at: p)
                DispatchQueue.main.async {
                    guard let self, gen == self.openQueryGen else { return }
                    self.openable = openQuery && hit.openable
                    self.textTarget = textQuery && hit.text
                }
            }
        }
    }

    /// Commits the deferred mouse-down once the pinch has outlived a
    /// fist-forming transient. Called every render frame.
    func commitPending(now: CFTimeInterval) {
        guard let t = pendingSince, !buttonDown, now - t >= downDelay else { return }
        pendingSince = nil
        buttonDown = true
        dragging = false
        downPos = pendingPos
        post(.leftMouseDown, at: downPos)
    }

    /// The "pinch" turned out to be a fist closing — forget it ever started.
    func cancelPending() {
        pendingSince = nil
    }

    func pinchUp(at p: CGPoint) {
        // Quick tap: released before the down committed — post the whole
        // click now, at the pinch-down point.
        if pendingSince != nil {
            pendingSince = nil
            buttonDown = true
            post(.leftMouseDown, at: pendingPos)
            buttonDown = false
            downPos = pendingPos
            post(.leftMouseUp, at: pendingPos)
            finishClick(wasDrag: false)
            return
        }
        guard buttonDown else { return }
        buttonDown = false
        // A click (never escaped the slop) releases exactly where it pressed.
        post(.leftMouseUp, at: dragging ? p : downPos)
        finishClick(wasDrag: dragging)
        dragging = false
    }

    private func finishClick(wasDrag: Bool) {
        // Content-aware open: a clean single click on a Finder file item gets
        // a second click appended, so ONE pinch opens it — double-click is a
        // Finder-only convention, buttons and links still get single clicks.
        if !wasDrag, openable, clickCount == 1 {
            clickCount = 2
            post(.leftMouseDown, at: downPos)
            post(.leftMouseUp, at: downPos)
        }
        openable = false
        // Clicks activate the app under the cursor, and activation is the
        // main thing that un-hides the cursor — re-assert on the next frame.
        lastHideAssert = 0
    }

    // MARK: - Content-aware click / target classification

    private static let systemWide = AXUIElementCreateSystemWide()
    /// Roles a Finder file item resolves to under the cursor: icon-view /
    /// desktop icons (AXImage), list & column view rows and cells, filenames.
    private static let openableRoles: Set<String> =
        ["AXImage", "AXCell", "AXRow", "AXTextField", "AXStaticText"]
    /// Roles that mean "you can type here" (dictation targets).
    private static let textRoles: Set<String> =
        ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]
    private let axQueue = DispatchQueue(label: "aircontrol.mouse.ax", qos: .userInteractive)
    private var openable = false
    private(set) var textTarget = false
    private var openQueryGen = 0

    private static func classify(at p: CGPoint) -> (openable: Bool, text: Bool) {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWide, Float(p.x), Float(p.y), &el) == .success,
              let el else { return (false, false) }
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return (false, false) }
        let text = isTextRole(role, element: el)
        var pid: pid_t = 0
        let inFinder = AXUIElementGetPid(el, &pid) == .success
            && NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
        return (inFinder && openableRoles.contains(role), text)
    }

    /// Known text roles, plus a fallback for web/Electron editors whose roles
    /// vary: any focused-style element exposing a selected-text range is a
    /// place a caret can live.
    private static func isTextRole(_ role: String, element: AXUIElement) -> Bool {
        if textRoles.contains(role) { return true }
        guard role != "AXStaticText" else { return false }
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                             &v) == .success
    }

    // MARK: - Dictation support

    /// Dictation begins while the pinch is still held: complete the click NOW
    /// (up at the down point) so the field gets focus and the caret lands —
    /// the continuing pinch belongs to the microphone, not the button.
    func completeClickEarly() {
        commitPending(now: CACurrentMediaTime()) // a still-pending down counts
        guard buttonDown, !dragging else { return }
        buttonDown = false
        post(.leftMouseUp, at: downPos)
        openable = false
        lastHideAssert = 0
    }

    /// Types a string into whatever has keyboard focus, as synthetic unicode
    /// key events — works identically in native apps, browsers, and Electron.
    /// Chunked on character boundaries (the event API caps the payload).
    func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.post(tap: .cghidEventTap)
            chunk.removeAll()
        }
        for ch in text {
            chunk.append(contentsOf: Array(String(ch).utf16))
            if chunk.count >= 18 { flush() }
        }
        flush()
    }

    /// Safety net — the system button must NEVER be left stuck down (mode
    /// toggled off mid-pinch, hand lost, app disabled, overlay closing).
    func releaseIfNeeded(at p: CGPoint? = nil) {
        pendingSince = nil // an uncommitted down just evaporates
        if buttonDown { pinchUp(at: p ?? lastClickPos) }
    }

    // MARK: - Scrolling

    private var scrollResidual = CGVector.zero

    /// Pixel-unit scroll wheel. Deltas arrive as fractions at render rate;
    /// the residual accumulator keeps sub-pixel motion instead of rounding it
    /// away, so slow scrolls stay smooth instead of stuttering.
    func scroll(dx: CGFloat, dy: CGFloat) {
        scrollResidual.dx += dx
        scrollResidual.dy += dy
        let ix = Int32(scrollResidual.dx.rounded())
        let iy = Int32(scrollResidual.dy.rounded())
        guard ix != 0 || iy != 0 else { return }
        scrollResidual.dx -= CGFloat(ix)
        scrollResidual.dy -= CGFloat(iy)
        let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                        wheelCount: 2, wheel1: iy, wheel2: ix, wheel3: 0)
        e?.post(tap: .cghidEventTap)
    }

    // MARK: - System cursor visibility

    private var cursorHidden = false
    private var hideCount = 0
    private var lastHideAssert: CFTimeInterval = 0

    /// In mouse mode the AirControl ring IS the cursor — the system arrow
    /// trailing it is noise. A single hide is NOT enough: macOS re-shows the
    /// cursor behind our back, most reliably when a synthetic click activates
    /// the app under it. So the hide is re-asserted on a short cadence while
    /// hidden (and forced right after every click); each hide bumps the
    /// WindowServer's per-connection count, so release balances all of them.
    func setCursorHidden(_ hidden: Bool) {
        guard hidden != cursorHidden else { return }
        cursorHidden = hidden
        if hidden {
            assertHide()
        } else {
            while hideCount > 0 {
                CGDisplayShowCursor(CGMainDisplayID())
                hideCount -= 1
            }
        }
    }

    /// Called every render frame while in mouse mode; cheap unless due.
    func reassertCursorHide(now: CFTimeInterval) {
        guard cursorHidden, now - lastHideAssert > 0.3 else { return }
        assertHide()
    }

    private func assertHide() {
        let cid = CGSMainConnectionID()
        CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        CGDisplayHideCursor(CGMainDisplayID())
        hideCount += 1
        lastHideAssert = CACurrentMediaTime()
    }

    private func post(_ type: CGEventType, at p: CGPoint) {
        let e = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        e?.post(tap: .cghidEventTap)
    }
}
