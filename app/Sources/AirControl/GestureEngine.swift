import CoreGraphics
import QuartzCore
import Vision

/// Everything the rest of the app needs to know about the hand this instant.
/// `pointer`/`anchor` are normalized [0,1] AFTER the edge-margin remap.
struct GestureState {
    var handVisible = false
    var pointer: CGPoint = .zero   // what the cursor tracks (fingertip or MCP per config)
    var anchor: CGPoint = .zero    // index MCP knuckle — what a drag tracks
    var pinchRaw: Double = 0
    var pinchSmooth: Double = 0
    var pinching = false
    var extendedCount = 0
    var swiping = false
    var swipeArmed = false         // palm paused long enough — stroke will count
    var thumbDir = 0               // fist + sideways thumb held: −1 left, +1 right, 0 none
    var peaceProgress: Double = 0  // ✌ held toward turning the app off
    var peaceEvent = false         // fired this frame: disable AirControl
    var swipeProgress: Double = 0  // signed −1…+1 toward firing
    var swipeEvent: Int?           // fired this frame: −1 left, +1 right
    var settling = false           // riding out the Space-switch animation
    var fps: Double = 0
}

/// Faithful Swift port of the Phase 1 gesture logic (phase1/index.html),
/// using the constants Ronak tuned by feel. Pure math — no AppKit — so it can
/// be unit-tested by replaying recorded landmark sequences.
final class GestureEngine {
    private var pinchSmooth: Double?
    private var pinching = false
    private var palmHist: [(t: CFTimeInterval, x: Double, y: Double)] = []
    private var lastPalmT: CFTimeInterval = 0
    private var lastSwipeTime: CFTimeInterval = -1e9
    private var lastSeen: CFTimeInterval = 0
    private var settleUntil: CFTimeInterval = 0
    private var frozenPointer: CGPoint?
    private var frozenAnchor: CGPoint?
    private let reentryDur: CFTimeInterval = 0.3
    private var armedSince: CFTimeInterval?
    private var stillSince: CFTimeInterval?
    private var lastPalm: (t: CFTimeInterval, x: Double, y: Double)?
    private var poseSince: CFTimeInterval?
    private var poseDir = 0
    private var poseFired = false
    private var peaceSince: CFTimeInterval?

    /// Called (from AppState) when macOS reports the active Space actually
    /// changed — freeze the pointer and suppress gestures while it animates.
    /// Keyed to the real event, never to the gesture, so a swipe that
    /// switches nothing can't freeze anything.
    func beginSettle(duration: CFTimeInterval) {
        settleUntil = max(settleUntil, CACurrentMediaTime() + duration)
    }

    /// Palm-gone gap that re-arms the swipe history. Well above one missed
    /// frame so a brief dropout mid-sweep doesn't wipe the gesture.
    private let palmGapReset: CFTimeInterval = 0.35
    private let handLostReset: CFTimeInterval = 0.3

    private static let fingerJoints: [(tip: VNHumanHandPoseObservation.JointName,
                                       pip: VNHumanHandPoseObservation.JointName)] = [
        (.indexTip, .indexPIP),
        (.middleTip, .middlePIP),
        (.ringTip, .ringPIP),
        (.littleTip, .littlePIP),
    ]
    private static let palmJoints: [VNHumanHandPoseObservation.JointName] =
        [.wrist, .indexMCP, .middleMCP, .ringMCP, .littleMCP]

    func process(_ frame: LandmarkFrame?, config: Config, now: CFTimeInterval) -> GestureState {
        var s = GestureState()

        guard let f = frame else {
            // Hand gone: swipe progress dies immediately; pinch releases after
            // a real gap so a grabbed window is dropped in place, not held.
            if now - lastSeen > handLostReset {
                pinching = false
                pinchSmooth = nil
            }
            s.pinching = pinching
            return s
        }
        lastSeen = now
        s.handVisible = true
        s.fps = f.fps
        s.pointer = remap(config.pointerAtKnuckle ? f.indexMCP : f.indexTip, config: config)
        s.anchor = remap(f.indexMCP, config: config)

        // --- Post-switch settle: while macOS animates the Space slide, the
        // hand is still finishing the swipe — freeze the pointer and suppress
        // every gesture so the transition can't be disturbed or look jittery.
        if now < settleUntil {
            s.settling = true
            s.pointer = frozenPointer ?? s.pointer
            s.anchor = frozenAnchor ?? s.anchor
            pinching = false
            pinchSmooth = nil
            palmHist.removeAll()
            s.pinching = false
            return s
        }
        // Re-entry: glide from the frozen point to the live hand instead of
        // teleporting the moment the settle ends.
        let sinceSettle = now - settleUntil
        if sinceSettle < reentryDur, let fp = frozenPointer, let fa = frozenAnchor {
            let t = sinceSettle / reentryDur
            let e = CGFloat(t * t * (3 - 2 * t)) // smoothstep
            s.pointer = lerp(fp, s.pointer, e)
            s.anchor = lerp(fa, s.anchor, e)
        } else {
            frozenPointer = s.pointer
            frozenAnchor = s.anchor
        }

        // --- Pinch: thumb-tip↔index-tip, normalized by hand size (wrist ↔
        // middle MCP — roughly constant for a hand regardless of pose) so it
        // works at any distance from the camera. EMA + hysteresis as in Phase 1.
        let middleMCP = f.joints[.middleMCP] ?? f.indexMCP
        let handSize = max(dist(f.wrist, middleMCP), 1e-6)
        let raw = dist(f.thumbTip, f.indexTip) / handSize
        let smooth = pinchSmooth.map { $0 + config.pinchAlpha * (raw - $0) } ?? raw
        pinchSmooth = smooth
        if pinching {
            if smooth > config.pinchThresh + config.pinchHyst { pinching = false }
        } else if smooth < config.pinchThresh {
            pinching = true
        }
        s.pinchRaw = raw
        s.pinchSmooth = smooth
        s.pinching = pinching

        // --- Finger extension: tip farther from wrist than PIP by a factor.
        // Naturally mutually exclusive with a pinch (pinch curls the index).
        var extended = 0
        var extFlags = [false, false, false, false] // index, middle, ring, little
        var curlFlags = [false, false, false, false]
        for (i, pair) in Self.fingerJoints.enumerated() {
            guard let tip = f.joints[pair.tip], let pip = f.joints[pair.pip] else { continue }
            let tipD = dist(f.wrist, tip)
            let pipD = max(dist(f.wrist, pip), 1e-6)
            if tipD > pipD * config.extendThresh {
                extended += 1
                extFlags[i] = true
            }
            curlFlags[i] = tipD < pipD // clearly folded, not just "not extended"
        }
        s.extendedCount = extended
        s.swiping = extended >= config.swipeMinFingers && !pinching

        // --- ✌ to turn off: index+middle extended, ring+little folded, held
        // with a visible meter — passing through the shape while opening or
        // closing the hand never lasts long enough to fire.
        if config.peaceOff, !pinching,
           extFlags[0], extFlags[1], curlFlags[2], curlFlags[3] {
            if peaceSince == nil { peaceSince = now }
            let progress = min((now - peaceSince!) / (config.peaceHoldMS / 1000), 1)
            s.peaceProgress = progress
            if progress >= 1 {
                peaceSince = nil
                s.peaceEvent = true
            }
        } else {
            peaceSince = nil
        }

        // --- Thumb-pose Space switch: fist with the thumb stuck out sideways,
        // pointing at the Space you want; hold briefly to fire. A static POSE,
        // not a motion — waves, pointing, and drags share nothing with it, so
        // it can't be misread, and it can't miss: hold until the meter fills.
        if config.thumbSwitch, !pinching {
            var curled = 0
            for pair in Self.fingerJoints {
                guard let tip = f.joints[pair.tip], let pip = f.joints[pair.pip] else { continue }
                if dist(f.wrist, tip) < dist(f.wrist, pip) * 1.0 { curled += 1 }
            }
            let thumbBase = f.joints[.thumbIP] ?? f.joints[.thumbMP] ?? f.wrist
            let dx = Double(f.thumbTip.x - thumbBase.x)
            let dy = Double(f.thumbTip.y - thumbBase.y)
            let sideways = abs(dx) > abs(dy) * 1.5
            let dir = dx > 0 ? 1 : -1
            if curled >= 3, sideways {
                if poseSince == nil || dir != poseDir {
                    poseSince = now
                    poseDir = dir
                    poseFired = false
                }
                s.thumbDir = dir
                let progress = min((now - poseSince!) / (config.thumbHoldMS / 1000), 1)
                s.swipeProgress = Double(dir) * progress
                if progress >= 1, !poseFired,
                   now - lastSwipeTime >= config.swipeCooldownMS / 1000 {
                    lastSwipeTime = now
                    poseFired = true
                    s.swipeProgress = 0
                    // Emit pre-inverted so AppState's swipeNatural transform
                    // lands on the thumb's literal direction — the thumb
                    // points AT the target Space, "natural push" doesn't apply.
                    s.swipeEvent = config.swipeNatural ? -dir : dir
                }
            } else {
                poseSince = nil
                poseDir = 0
            }
        } else {
            poseSince = nil
            poseDir = 0
        }

        // --- Swipe: arm-then-stroke. A deliberate swipe starts from a
        // momentary pause (present the palm, then stroke); a wave is
        // continuous motion that never pauses, so it never arms. Once armed,
        // net palm displacement over a time window fires the swipe, still
        // gated on straightness + horizontality. Superseded as the Space
        // trigger by the thumb pose when that's enabled.
        if s.swiping, !config.thumbSwitch {
            let palmPoints = Self.palmJoints.compactMap { f.joints[$0] }
            if !palmPoints.isEmpty {
                let palmX = Double(palmPoints.reduce(0) { $0 + $1.x }) / Double(palmPoints.count)
                let palmY = Double(palmPoints.reduce(0) { $0 + $1.y }) / Double(palmPoints.count)
                if now - lastPalmT > palmGapReset {
                    palmHist.removeAll()
                    armedSince = nil
                    stillSince = nil
                    lastPalm = nil
                }
                lastPalmT = now

                if armedSince == nil, let lp = lastPalm {
                    let dt = max(now - lp.t, 1e-3)
                    let speed = Double(hypot(palmX - lp.x, palmY - lp.y)) / dt
                    if speed < config.swipeArmMaxSpeed {
                        if stillSince == nil { stillSince = now }
                        if now - stillSince! >= config.swipeArmMS / 1000 {
                            armedSince = now
                            palmHist.removeAll() // stroke measures from the pause
                        }
                    } else {
                        stillSince = nil
                    }
                }
                lastPalm = (t: now, x: palmX, y: palmY)
                s.swipeArmed = armedSince != nil

                if armedSince != nil {
                    palmHist.append((t: now, x: palmX, y: palmY))
                    while palmHist.count > 1, now - palmHist[0].t > config.swipeMaxTimeMS / 1000 {
                        palmHist.removeFirst()
                    }
                    let travel = palmHist[palmHist.count - 1].x - palmHist[0].x
                    // A swipe is ONE straight horizontal stroke; a wave doubles
                    // back (net ≪ path) and arcs vertically. Gate on both.
                    var pathX = 0.0
                    for i in 1..<palmHist.count { pathX += abs(palmHist[i].x - palmHist[i - 1].x) }
                    let netY = abs(palmHist[palmHist.count - 1].y - palmHist[0].y)
                    let straight = abs(travel) >= pathX * config.swipeStraightness
                    let horizontal = netY <= max(abs(travel), 0.02) * config.swipeMaxVertRatio
                    guard straight, horizontal else {
                        s.swipeProgress = 0
                        return s
                    }
                    s.swipeProgress = min(max(travel / config.swipeDist, -1), 1)
                    if now - lastSwipeTime >= config.swipeCooldownMS / 1000,
                       abs(travel) >= config.swipeDist {
                        lastSwipeTime = now
                        palmHist.removeAll()
                        s.swipeProgress = 0
                        s.swipeEvent = travel > 0 ? 1 : -1
                        armedSince = nil
                        stillSince = nil
                    }
                }
            }
        } else if poseSince == nil { // don't stomp the thumb meter
            s.swipeProgress = 0 // history ages out; a real gap re-arms it
            armedSince = nil
            stillSince = nil
            lastPalm = nil
        }

        return s
    }

    /// Camera space → [0,1] hand range: the calibrated comfortable rect when
    /// one exists (PLAN §5.4 — small personal box, full desktop reach, no
    /// stretching), else the symmetric edge-margin default.
    private func remap(_ p: CGPoint, config: Config) -> CGPoint {
        if let c = config.calibration {
            let w = CGFloat(max(c.maxX - c.minX, 0.05))
            let h = CGFloat(max(c.maxY - c.minY, 0.05))
            return CGPoint(x: min(max((p.x - CGFloat(c.minX)) / w, 0), 1),
                           y: min(max((p.y - CGFloat(c.minY)) / h, 0), 1))
        }
        let m = CGFloat(config.margin)
        let span = max(1 - 2 * m, 0.01)
        return CGPoint(x: min(max((p.x - m) / span, 0), 1),
                       y: min(max((p.y - m) / span, 0), 1))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}
