import CoreGraphics
import QuartzCore

/// 1€ filter (Casiez et al.) — jitter-adaptive smoothing: heavy when the
/// signal is nearly still (steady pointer), light when it moves fast (no lag).
final class OneEuroFilter {
    var minCutoff: Double
    var beta: Double
    var dCutoff: Double

    private var xPrev: Double?
    private var dxPrev: Double = 0
    private var tPrev: CFTimeInterval?

    init(minCutoff: Double, beta: Double, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    func filter(_ x: Double, at t: CFTimeInterval) -> Double {
        guard let xp = xPrev, let tp = tPrev, t > tp else {
            xPrev = x
            tPrev = t
            return x
        }
        let dt = t - tp
        let dx = (x - xp) / dt
        let dxHat = lowpass(dx, prev: dxPrev, alpha: alpha(cutoff: dCutoff, dt: dt))
        let cutoff = minCutoff + beta * abs(dxHat)
        let xHat = lowpass(x, prev: xp, alpha: alpha(cutoff: cutoff, dt: dt))
        xPrev = xHat
        dxPrev = dxHat
        tPrev = t
        return xHat
    }

    func reset() {
        xPrev = nil
        dxPrev = 0
        tPrev = nil
    }

    private func alpha(cutoff: Double, dt: Double) -> Double {
        let r = 2 * .pi * cutoff * dt
        return r / (r + 1)
    }

    private func lowpass(_ x: Double, prev: Double, alpha: Double) -> Double {
        prev + alpha * (x - prev)
    }
}

/// Per-axis 1€ filtering for a 2D point.
final class PointFilter {
    private let fx: OneEuroFilter
    private let fy: OneEuroFilter

    init(minCutoff: Double = 1.0, beta: Double = 2.0) {
        fx = OneEuroFilter(minCutoff: minCutoff, beta: beta)
        fy = OneEuroFilter(minCutoff: minCutoff, beta: beta)
    }

    func filter(_ p: CGPoint, at t: CFTimeInterval) -> CGPoint {
        CGPoint(x: fx.filter(p.x, at: t), y: fy.filter(p.y, at: t))
    }

    func setParams(minCutoff: Double, beta: Double) {
        fx.minCutoff = minCutoff
        fy.minCutoff = minCutoff
        fx.beta = beta
        fy.beta = beta
    }

    func reset() {
        fx.reset()
        fy.reset()
    }
}
