import AppKit

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
    private var dragging = false
    private var downPos = CGPoint.zero
    private var clickCount: Int64 = 1
    private var lastClickTime: CFTimeInterval = -1e9
    private var lastClickPos = CGPoint.zero
    private var lastMoved: CGPoint?
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Multi-click only counts when the next pinch lands about here.
    private let multiClickRadius: CGFloat = 12

    func move(to p: CGPoint) {
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

    func pinchDown(at p: CGPoint, now: CFTimeInterval) {
        guard !buttonDown else { return }
        buttonDown = true
        dragging = false
        downPos = p
        if now - lastClickTime < NSEvent.doubleClickInterval,
           hypot(p.x - lastClickPos.x, p.y - lastClickPos.y) < multiClickRadius {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now
        lastClickPos = p
        post(.leftMouseDown, at: p)
    }

    func pinchUp(at p: CGPoint) {
        guard buttonDown else { return }
        buttonDown = false
        // A click (never escaped the slop) releases exactly where it pressed.
        post(.leftMouseUp, at: dragging ? p : downPos)
        dragging = false
    }

    /// Safety net — the system button must NEVER be left stuck down (mode
    /// toggled off mid-pinch, hand lost, app disabled, overlay closing).
    func releaseIfNeeded(at p: CGPoint? = nil) {
        if buttonDown { pinchUp(at: p ?? lastClickPos) }
    }

    private func post(_ type: CGEventType, at p: CGPoint) {
        let e = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        e?.post(tap: .cghidEventTap)
    }
}
