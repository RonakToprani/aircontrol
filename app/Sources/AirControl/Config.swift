import Foundation
import Combine

/// Every tunable in one place, seeded with the values Ronak dialed in by feel
/// on the Phase 1 web prototype. Nothing gesture-related is hardcoded anywhere
/// else — each field is bound to a live slider in the tuning panel.
struct Config: Codable, Equatable {
    // Pointer
    var posAlpha: Double = 0.35        // render-easing factor, per 60fps frame
    var oneEuroMinCutoff: Double = 1.0 // 1€: smoothing floor (lower = steadier at rest)
    var oneEuroBeta: Double = 2.0      // 1€: speed responsiveness (higher = less lag when fast)
    var margin: Double = 0.15          // camera-edge dead-zone fraction
    var pointerAtKnuckle: Bool = true  // cursor tracks index MCP instead of fingertip
    var jumpRejectDist: Double = 0.25  // 1-frame wrist jump beyond this is a misdetection

    // Pinch
    var pinchAlpha: Double = 0.50      // pinch-signal EMA (higher = more responsive)
    var pinchThresh: Double = 0.42     // engage below this (normalized by hand size)
    var pinchHyst: Double = 0.12       // release only above thresh + hyst

    // 4-finger swipe
    var swipeDist: Double = 0.16       // normalized-x travel that fires a swipe
    var swipeMaxTimeMS: Double = 500   // travel must happen within this window
    var swipeCooldownMS: Double = 1650 // lockout so one sweep fires once
    var swipeMinFingers: Int = 3       // extended fingers required to arm
    var extendThresh: Double = 1.08    // tip-vs-PIP wrist-distance ratio = "extended"
    var swipeStraightness: Double = 0.8  // net x-travel ÷ total x-path — rejects back-and-forth waves
    var swipeMaxVertRatio: Double = 0.6  // max vertical drift ÷ horizontal travel — rejects arcs
    var swipeArmMS: Double = 200         // open palm must hold ~still this long to arm the stroke
    var swipeArmMaxSpeed: Double = 0.35  // palm speed (normalized/s) that still counts as "holding still"

    // Multi-display mapping (M2, PLAN §5.3 Model B)
    var useModelA: Bool = true         // Ronak's 2-display bake-off pick: hand range → whole desktop
    var crossOvershoot: Double = 0.08  // pointer must push past the seam by this fraction of the display
    var crossDwellMS: Double = 350     // …or hold any pressure against the seam this long
    var crossLockoutMS: Double = 500   // same-seam backward re-cross blocked this long (chaining stays free)
    var anchorDecayRate: Double = 3.0  // how fast the entry-edge anchor recenters, ∝ hand speed

    // Real windows (M3)
    var useMockWindows: Bool = false     // practice on mock windows instead of real ones
    var raiseOnGrab: Bool = true         // grabbing a window brings it to front, like a mouse click
    var axWriteMinIntervalMS: Double = 33 // floor between AX position writes; latency adapts above it
    var stickyHoverPx: Double = 16       // pointer must exit target frame by this before retargeting

    // Spaces (M4 pulled forward)
    var switchSpaces: Bool = true      // fired swipe posts ⌃←/⌃→ (needs Accessibility)
    var thumbSwitch: Bool = true       // Space switch = fist + thumb pointing sideways (replaces motion swipe)
    var thumbHoldMS: Double = 300      // hold the thumb pose this long to fire
    var swipeNatural: Bool = true      // hand pushes the desktop: move right → Space on the left
    var postSwipeSettleMS: Double = 1200 // freeze pointer + gestures while the slide animates

    init() {}

    /// Every field decodes independently with its default as fallback, so a
    /// config saved by an older build (missing newer keys) keeps its values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        posAlpha = (try? c.decode(Double.self, forKey: .posAlpha)) ?? d.posAlpha
        oneEuroMinCutoff = (try? c.decode(Double.self, forKey: .oneEuroMinCutoff)) ?? d.oneEuroMinCutoff
        oneEuroBeta = (try? c.decode(Double.self, forKey: .oneEuroBeta)) ?? d.oneEuroBeta
        margin = (try? c.decode(Double.self, forKey: .margin)) ?? d.margin
        pointerAtKnuckle = (try? c.decode(Bool.self, forKey: .pointerAtKnuckle)) ?? d.pointerAtKnuckle
        jumpRejectDist = (try? c.decode(Double.self, forKey: .jumpRejectDist)) ?? d.jumpRejectDist
        pinchAlpha = (try? c.decode(Double.self, forKey: .pinchAlpha)) ?? d.pinchAlpha
        pinchThresh = (try? c.decode(Double.self, forKey: .pinchThresh)) ?? d.pinchThresh
        pinchHyst = (try? c.decode(Double.self, forKey: .pinchHyst)) ?? d.pinchHyst
        swipeDist = (try? c.decode(Double.self, forKey: .swipeDist)) ?? d.swipeDist
        swipeMaxTimeMS = (try? c.decode(Double.self, forKey: .swipeMaxTimeMS)) ?? d.swipeMaxTimeMS
        swipeCooldownMS = (try? c.decode(Double.self, forKey: .swipeCooldownMS)) ?? d.swipeCooldownMS
        swipeMinFingers = (try? c.decode(Int.self, forKey: .swipeMinFingers)) ?? d.swipeMinFingers
        extendThresh = (try? c.decode(Double.self, forKey: .extendThresh)) ?? d.extendThresh
        swipeStraightness = (try? c.decode(Double.self, forKey: .swipeStraightness)) ?? d.swipeStraightness
        swipeMaxVertRatio = (try? c.decode(Double.self, forKey: .swipeMaxVertRatio)) ?? d.swipeMaxVertRatio
        swipeArmMS = (try? c.decode(Double.self, forKey: .swipeArmMS)) ?? d.swipeArmMS
        swipeArmMaxSpeed = (try? c.decode(Double.self, forKey: .swipeArmMaxSpeed)) ?? d.swipeArmMaxSpeed
        useModelA = (try? c.decode(Bool.self, forKey: .useModelA)) ?? d.useModelA
        crossOvershoot = (try? c.decode(Double.self, forKey: .crossOvershoot)) ?? d.crossOvershoot
        crossDwellMS = (try? c.decode(Double.self, forKey: .crossDwellMS)) ?? d.crossDwellMS
        crossLockoutMS = (try? c.decode(Double.self, forKey: .crossLockoutMS)) ?? d.crossLockoutMS
        anchorDecayRate = (try? c.decode(Double.self, forKey: .anchorDecayRate)) ?? d.anchorDecayRate
        useMockWindows = (try? c.decode(Bool.self, forKey: .useMockWindows)) ?? d.useMockWindows
        axWriteMinIntervalMS = (try? c.decode(Double.self, forKey: .axWriteMinIntervalMS)) ?? d.axWriteMinIntervalMS
        stickyHoverPx = (try? c.decode(Double.self, forKey: .stickyHoverPx)) ?? d.stickyHoverPx
        switchSpaces = (try? c.decode(Bool.self, forKey: .switchSpaces)) ?? d.switchSpaces
        thumbSwitch = (try? c.decode(Bool.self, forKey: .thumbSwitch)) ?? d.thumbSwitch
        thumbHoldMS = (try? c.decode(Double.self, forKey: .thumbHoldMS)) ?? d.thumbHoldMS
        raiseOnGrab = (try? c.decode(Bool.self, forKey: .raiseOnGrab)) ?? d.raiseOnGrab
        swipeNatural = (try? c.decode(Bool.self, forKey: .swipeNatural)) ?? d.swipeNatural
        postSwipeSettleMS = (try? c.decode(Double.self, forKey: .postSwipeSettleMS)) ?? d.postSwipeSettleMS
    }
}

@MainActor
final class ConfigStore: ObservableObject {
    private static let key = "aircontrol.config"

    @Published var config: Config {
        didSet {
            guard config != oldValue else { return }
            if let data = try? JSONEncoder().encode(config) {
                UserDefaults.standard.set(data, forKey: Self.key)
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Config.self, from: data) {
            config = saved
        } else {
            config = Config()
        }
    }

    func resetToDefaults() {
        config = Config()
    }
}
