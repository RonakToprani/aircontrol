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
