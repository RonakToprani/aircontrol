import AppKit
import ApplicationServices

/// A real on-screen window AirControl can drag: a CGWindowList entry resolved
/// to its AXUIElement. Frames are in CG coordinates (origin top-left of the
/// primary display, y down) — the space both CGWindowList and AX use.
struct TargetWindow {
    let ax: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID
    var frame: CGRect
    let appName: String
}

/// M3: find the real window under the pointer and move it via Accessibility.
/// Every AX call runs on a private queue — position writes on slow apps
/// (Electron, Chrome) can take tens of ms and must never block the render
/// loop. Drag writes are coalesced (only the latest target is written) and
/// self-paced: the next write waits out max(configured floor, measured write
/// latency), so native apps track live and slow apps degrade gracefully while
/// the overlay's ghost outline stays the 60fps feedback. Release always gets
/// a final guaranteed write.
final class WindowMover {
    /// EMA'd milliseconds per AX position write, delivered on the main thread.
    var onLatency: ((Double) -> Void)?

    private let queue = DispatchQueue(label: "aircontrol.ax", qos: .userInteractive)
    private var minWriteInterval: Double = 0.033 // seconds; tunable via panel
    private var dragTarget: TargetWindow?
    private var pendingOrigin: CGPoint?
    private var writeScheduled = false
    private var latencyEMA: Double = 0

    func setMinWriteInterval(ms: Double) {
        queue.async { self.minWriteInterval = ms / 1000 }
    }

    func queryWindow(at cgPoint: CGPoint, completion: @escaping (TargetWindow?) -> Void) {
        queue.async {
            let result = self.findWindow(at: cgPoint)
            DispatchQueue.main.async { completion(result) }
        }
    }

    func beginDrag(_ target: TargetWindow) {
        queue.async {
            self.dragTarget = target
            self.pendingOrigin = nil
        }
    }

    func drag(to origin: CGPoint) {
        queue.async {
            self.pendingOrigin = origin
            self.pumpWrites()
        }
    }

    func endDrag(at origin: CGPoint?) {
        queue.async {
            if let t = self.dragTarget, let o = origin ?? self.pendingOrigin {
                self.write(t, o) // drop-commit: the release position always lands
            }
            self.dragTarget = nil
            self.pendingOrigin = nil
        }
    }

    // MARK: - on queue

    private func pumpWrites() {
        guard !writeScheduled, let t = dragTarget, let o = pendingOrigin else { return }
        pendingOrigin = nil
        writeScheduled = true
        let started = CACurrentMediaTime()
        write(t, o)
        let elapsed = CACurrentMediaTime() - started
        latencyEMA = latencyEMA == 0 ? elapsed : latencyEMA * 0.8 + elapsed * 0.2
        if let cb = onLatency {
            let ms = latencyEMA * 1000
            DispatchQueue.main.async { cb(ms) }
        }
        let delay = max(minWriteInterval, latencyEMA)
        queue.asyncAfter(deadline: .now() + delay) {
            self.writeScheduled = false
            self.pumpWrites()
        }
    }

    private func write(_ t: TargetWindow, _ origin: CGPoint) {
        var p = origin
        if let v = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(t.ax, kAXPositionAttribute as CFString, v)
        }
    }

    private func findWindow(at point: CGPoint) -> TargetWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        let myPID = getpid()
        for info in list { // front-to-back — the first hit is the topmost window
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pidNum = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pid_t(pidNum.int32Value) != myPID,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.05,
                  let boundsAny = info[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: boundsAny as! CFDictionary),
                  frame.contains(point)
            else { continue }
            let pid = pid_t(pidNum.int32Value)
            let wid = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let name = info[kCGWindowOwnerName as String] as? String ?? "?"
            guard let ax = resolveAX(pid: pid, frame: frame) else { return nil }
            // Refuse windows whose position can't be written (system panels).
            var settable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(ax, kAXPositionAttribute as CFString, &settable)
            guard settable.boolValue else { return nil }
            return TargetWindow(ax: ax, pid: pid, windowID: CGWindowID(wid), frame: frame, appName: name)
        }
        return nil
    }

    /// Match the owning PID's AX windows to the CGWindowList frame — the two
    /// APIs share the coordinate space, so the closest frame (within a small
    /// tolerance) is the same window.
    private func resolveAX(pid: pid_t, frame: CGRect) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return nil }
        var best: (win: AXUIElement, score: CGFloat)?
        for w in windows {
            guard let f = axFrame(w) else { continue }
            let score = abs(f.minX - frame.minX) + abs(f.minY - frame.minY)
                + abs(f.width - frame.width) + abs(f.height - frame.height)
            if best == nil || score < best!.score { best = (w, score) }
        }
        guard let b = best, b.score < 8 else { return nil }
        return b.win
    }

    private func axFrame(_ w: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &p),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }
}
