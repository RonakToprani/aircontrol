import CoreGraphics
import QuartzCore
import Vision

/// One detection's worth of hand data, in AirControl's canonical coordinates:
/// normalized [0,1], origin bottom-left, mirrored so moving your hand right
/// increases x. Matches the conventions the Phase 1 gesture logic was tuned in.
struct LandmarkFrame {
    /// Control points, 1€-filtered.
    var indexTip: CGPoint
    var indexMCP: CGPoint
    var thumbTip: CGPoint
    var wrist: CGPoint
    /// All confidently-detected joints, RAW (unfiltered) — for the hand
    /// preview, so it shows what the tracker actually sees.
    var joints: [VNHumanHandPoseObservation.JointName: CGPoint]
    /// Smoothed successful-detections-per-second (the Phase 1 "Detect FPS").
    var fps: Double
    var timestamp: CFTimeInterval
}
