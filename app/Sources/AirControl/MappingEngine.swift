import AppKit
import QuartzCore

/// What the mapper hands the overlay each frame: global AppKit coordinates.
struct MappedPointer {
    var pointer: CGPoint
    var anchor: CGPoint
    var screen: NSScreen
    var screenChanged: Bool
    var pressure: Double   // 0…1 toward a crossing commit
    var pressureDX: Int    // seam being pushed: −1/+1 horizontal, 0 none
    var pressureDY: Int    // −1/+1 vertical, 0 none
}

/// M2 — PLAN §5.3 Model B (chosen): the full hand range maps to the ACTIVE
/// display only, for maximum precision and minimal arm travel. Crossing to a
/// neighbor works like a mouse: the pointer reaches a shared edge and the
/// hand keeps pushing — commit on overshoot distance OR sustained pressure.
/// Every Phase 1.5 defect is designed out:
///  - trigger is gated on the POINTER vs display geometry, never raw hand space
///  - after a cross, re-crossing the same seam backward is locked out briefly;
///    pushing FORWARD through the next seam is never locked (chained crossing)
///  - entry-edge re-anchor keeps the motion continuous, then the anchor decays
///    back to the canonical mapping while the hand moves (VR-style drift
///    correction) — reach recovers within about a second, no clutch gesture
///  - neighbor topology is derived from real NSScreen frames each call, any
///    orientation/arrangement; gaps are collapsed (entry point clamps onto the
///    neighbor, the pointer can never live in dead space)
/// Model A (whole-desktop union mapping) stays one config toggle away as the
/// M2 bake-off comparison.
final class PointerMapper {
    private var activeScreen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var anchorOffset = CGVector.zero
    private var lastNorm: CGPoint?
    private var lastTime: CFTimeInterval = 0
    private var pressureSince: CFTimeInterval?
    private var lastCrossTime: CFTimeInterval = -1e9
    private var lastCrossDir = (dx: 0, dy: 0)
    private var lastScreenReturned: NSScreen?
    private var pinchLast: CGPoint?
    private var precisionOffset = CGVector.zero

    /// Speed band for precision-on-pinch, in hand-ranges/second: at or below
    /// the low end drag motion is scaled by `precisionOnPinch`; at the high
    /// end it passes through 1:1 (smoothstepped between), so placing is
    /// steady but traveling across displays costs no extra hand travel.
    private let precisionSpeedLo = 0.25
    private let precisionSpeedHi = 1.0

    func map(pointerNorm pIn: CGPoint, anchorNorm aIn: CGPoint, pinching: Bool,
             config: Config, now: CFTimeInterval) -> MappedPointer {
        // Hand speed drives both precision gain and offset decay.
        let dt = now - lastTime
        var speed = 0.0
        if let ln = lastNorm, dt < 0.2 {
            speed = Double(hypot(pIn.x - ln.x, pIn.y - ln.y)) / max(dt, 1e-3)
        }
        lastNorm = pIn
        lastTime = now

        // Precision-on-pinch (PLAN §5.2), speed-adaptive: slow drag motion is
        // scaled down (steady placement); fast motion passes through 1:1. The
        // scaling accumulates as an offset which, after release, DECAYS away
        // while the hand moves — the pointer re-syncs invisibly, never jumps.
        if pinching, config.precisionOnPinch < 0.999 {
            if let last = pinchLast, dt < 0.2 {
                let t = min(max((speed - precisionSpeedLo) / (precisionSpeedHi - precisionSpeedLo), 0), 1)
                let gain = config.precisionOnPinch
                    + (1 - config.precisionOnPinch) * (t * t * (3 - 2 * t))
                precisionOffset.dx += (pIn.x - last.x) * CGFloat(gain - 1)
                precisionOffset.dy += (pIn.y - last.y) * CGFloat(gain - 1)
            }
            pinchLast = pIn
        } else {
            pinchLast = nil
            let decay = CGFloat(min(1, config.anchorDecayRate * speed * min(dt, 0.1)))
            precisionOffset.dx *= 1 - decay
            precisionOffset.dy *= 1 - decay
        }
        let p = CGPoint(x: pIn.x + precisionOffset.dx, y: pIn.y + precisionOffset.dy)
        let a = CGPoint(x: aIn.x + precisionOffset.dx, y: aIn.y + precisionOffset.dy)

        if config.useModelA { return mapModelA(p, a) }

        // Display set may have changed under us (hot-plug).
        if !NSScreen.screens.contains(activeScreen) {
            activeScreen = NSScreen.main ?? NSScreen.screens[0]
            anchorOffset = .zero
        }
        let f = activeScreen.frame
        var raw = CGPoint(x: f.origin.x + p.x * f.width + anchorOffset.dx,
                          y: f.origin.y + p.y * f.height + anchorOffset.dy)

        // Recentering decay: while the hand moves, slew the entry-edge anchor
        // back toward the canonical mapping at a rate ∝ hand speed, so the
        // correction hides inside the user's own motion.
        let anchorDecay = CGFloat(min(1, config.anchorDecayRate * speed * min(dt, 0.1)))
        anchorOffset.dx *= 1 - anchorDecay
        anchorOffset.dy *= 1 - anchorDecay

        // Edge pressure from the unclamped overshoot.
        var dir = (dx: 0, dy: 0)
        var overPx: CGFloat = 0
        if raw.x > f.maxX { dir = (1, 0); overPx = raw.x - f.maxX }
        else if raw.x < f.minX { dir = (-1, 0); overPx = f.minX - raw.x }
        else if raw.y > f.maxY { dir = (0, 1); overPx = raw.y - f.maxY }
        else if raw.y < f.minY { dir = (0, -1); overPx = f.minY - raw.y }

        var pressure = 0.0
        var changed = false
        if dir != (0, 0), let neighbor = neighbor(dx: dir.dx, dy: dir.dy, at: raw) {
            // Lockout applies ONLY to bouncing straight back through the seam
            // just crossed; pushing onward through the next seam stays free.
            let locked = dir.dx == -lastCrossDir.dx && dir.dy == -lastCrossDir.dy
                && now - lastCrossTime < config.crossLockoutMS / 1000
            if locked {
                pressureSince = nil
                dir = (0, 0)
            } else {
                if pressureSince == nil { pressureSince = now }
                let commitPx = CGFloat(config.crossOvershoot) * (dir.dx != 0 ? f.width : f.height)
                let byDistance = Double(overPx / max(commitPx, 1))
                let byDwell = (now - pressureSince!) / (config.crossDwellMS / 1000)
                pressure = min(1, max(byDistance, byDwell))
                if pressure >= 1 {
                    let entry = entryPoint(into: neighbor, from: raw, dx: dir.dx, dy: dir.dy)
                    activeScreen = neighbor
                    let nf = neighbor.frame
                    let base = CGPoint(x: nf.origin.x + p.x * nf.width,
                                       y: nf.origin.y + p.y * nf.height)
                    anchorOffset = CGVector(dx: entry.x - base.x, dy: entry.y - base.y)
                    lastCrossTime = now
                    lastCrossDir = dir
                    pressureSince = nil
                    changed = true
                    raw = entry
                    pressure = 0
                    dir = (0, 0)
                }
            }
        } else {
            pressureSince = nil
            if dir != (0, 0) { dir = (0, 0) } // pushing an edge with no neighbor
        }

        let af = activeScreen.frame
        let pointer = clamp(raw, to: af)
        let anchorPt = clamp(CGPoint(x: af.origin.x + a.x * af.width + anchorOffset.dx,
                                     y: af.origin.y + a.y * af.height + anchorOffset.dy), to: af)
        let screenChanged = changed || lastScreenReturned !== activeScreen
        lastScreenReturned = activeScreen
        return MappedPointer(pointer: pointer, anchor: anchorPt, screen: activeScreen,
                             screenChanged: screenChanged,
                             pressure: pressure, pressureDX: dir.dx, pressureDY: dir.dy)
    }

    /// Model A comparison: hand range → bounding box of all displays; a point
    /// landing in dead space snaps to the screen nearest it.
    private func mapModelA(_ p: CGPoint, _ a: CGPoint) -> MappedPointer {
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        func place(_ n: CGPoint) -> (CGPoint, NSScreen) {
            let g = CGPoint(x: union.origin.x + n.x * union.width,
                            y: union.origin.y + n.y * union.height)
            if let s = NSScreen.screens.first(where: { $0.frame.contains(g) }) { return (g, s) }
            let s = NSScreen.screens.min {
                distanceSq(g, clamp(g, to: $0.frame)) < distanceSq(g, clamp(g, to: $1.frame))
            }!
            return (clamp(g, to: s.frame), s)
        }
        let (pt, screen) = place(p)
        let (an, _) = place(a)
        let screenChanged = lastScreenReturned !== screen
        lastScreenReturned = screen
        activeScreen = screen
        return MappedPointer(pointer: pt, anchor: an, screen: screen,
                             screenChanged: screenChanged,
                             pressure: 0, pressureDX: 0, pressureDY: 0)
    }

    /// Nearest screen strictly in the pushed direction with perpendicular
    /// overlap — any seam orientation, offset arrangements included.
    private func neighbor(dx: Int, dy: Int, at point: CGPoint) -> NSScreen? {
        let f = activeScreen.frame
        let candidates = NSScreen.screens.filter { s in
            guard s !== activeScreen else { return false }
            let sf = s.frame
            if dx == 1 { return sf.minX >= f.maxX - 1 && overlapY(sf, f) > 0 }
            if dx == -1 { return sf.maxX <= f.minX + 1 && overlapY(sf, f) > 0 }
            if dy == 1 { return sf.minY >= f.maxY - 1 && overlapX(sf, f) > 0 }
            if dy == -1 { return sf.maxY <= f.minY + 1 && overlapX(sf, f) > 0 }
            return false
        }
        // Prefer the neighbor whose span contains the pointer's perpendicular
        // coordinate; fall back to the largest shared span.
        if dx != 0 {
            return candidates.first { point.y >= $0.frame.minY && point.y <= $0.frame.maxY }
                ?? candidates.max { overlapY($0.frame, f) < overlapY($1.frame, f) }
        }
        return candidates.first { point.x >= $0.frame.minX && point.x <= $0.frame.maxX }
            ?? candidates.max { overlapX($0.frame, f) < overlapX($1.frame, f) }
    }

    private func entryPoint(into s: NSScreen, from raw: CGPoint, dx: Int, dy: Int) -> CGPoint {
        let f = s.frame
        var p = raw
        if dx == 1 { p.x = f.minX + 1 } else if dx == -1 { p.x = f.maxX - 1 }
        if dy == 1 { p.y = f.minY + 1 } else if dy == -1 { p.y = f.maxY - 1 }
        return clamp(p, to: f) // gap-collapse: land ON the neighbor, never between
    }

    private func overlapY(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxY, b.maxY) - max(a.minY, b.minY))
    }

    private func overlapX(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(0, min(a.maxX, b.maxX) - max(a.minX, b.minX))
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX - 1), y: min(max(p.y, r.minY), r.maxY - 1))
    }

    private func distanceSq(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }
}
