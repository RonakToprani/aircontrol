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
    private var palmHist: [(t: CFTimeInterval, x: Double)] = []
    private var lastPalmT: CFTimeInterval = 0
    private var lastSwipeTime: CFTimeInterval = -1e9
    private var lastSeen: CFTimeInterval = 0
    private var settleUntil: CFTimeInterval = 0
    private var frozenPointer: CGPoint?
    private var frozenAnchor: CGPoint?

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
        s.pointer = remap(config.pointerAtKnuckle ? f.indexMCP : f.indexTip,
                          margin: config.margin)
        s.anchor = remap(f.indexMCP, margin: config.margin)

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
        frozenPointer = s.pointer
        frozenAnchor = s.anchor

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
        for pair in Self.fingerJoints {
            guard let tip = f.joints[pair.tip], let pip = f.joints[pair.pip] else { continue }
            let tipD = dist(f.wrist, tip)
            let pipD = max(dist(f.wrist, pip), 1e-6)
            if tipD > pipD * config.extendThresh { extended += 1 }
        }
        s.extendedCount = extended
        s.swiping = extended >= config.swipeMinFingers && !pinching

        // --- Swipe: net palm-center displacement over a time window.
        if s.swiping {
            let palmPoints = Self.palmJoints.compactMap { f.joints[$0] }
            if !palmPoints.isEmpty {
                let palmX = palmPoints.reduce(0) { $0 + $1.x } / CGFloat(palmPoints.count)
                if now - lastPalmT > palmGapReset { palmHist.removeAll() }
                lastPalmT = now
                palmHist.append((t: now, x: palmX))
                while palmHist.count > 1, now - palmHist[0].t > config.swipeMaxTimeMS / 1000 {
                    palmHist.removeFirst()
                }
                let travel = Double(palmHist[palmHist.count - 1].x - palmHist[0].x)
                s.swipeProgress = min(max(travel / config.swipeDist, -1), 1)
                if now - lastSwipeTime >= config.swipeCooldownMS / 1000,
                   abs(travel) >= config.swipeDist {
                    lastSwipeTime = now
                    palmHist.removeAll()
                    s.swipeProgress = 0
                    s.swipeEvent = travel > 0 ? 1 : -1
                    if config.switchSpaces {
                        settleUntil = now + config.postSwipeSettleMS / 1000
                    }
                }
            }
        } else {
            s.swipeProgress = 0 // history ages out; a real gap re-arms it
        }

        return s
    }

    private func remap(_ p: CGPoint, margin: Double) -> CGPoint {
        let m = CGFloat(margin)
        let span = max(1 - 2 * m, 0.01)
        return CGPoint(x: min(max((p.x - m) / span, 0), 1),
                       y: min(max((p.y - m) / span, 0), 1))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }
}
