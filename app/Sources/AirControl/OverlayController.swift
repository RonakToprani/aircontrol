import AppKit
import QuartzCore

/// A borderless, click-through window covering one screen, drawing the
/// AirControl pointer (ring + fingertip dot) and an M0 diagnostics line.
/// The pointer is eased toward the latest detection every render frame via
/// CADisplayLink — the Phase 1 two-rate smoothness architecture.
final class OverlayController {
    private var window: NSWindow?
    private let view: OverlayView

    init(screen: NSScreen) {
        view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        let w = NSWindow(contentRect: screen.frame,
                         styleMask: .borderless,
                         backing: .buffered,
                         defer: false)
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        w.contentView = view
        window = w
    }

    func show() { window?.orderFrontRegardless() }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    func update(frame: LandmarkFrame?) { view.setDetection(frame) }
}

final class OverlayView: NSView {
    // Phase 1 tuned constants (seed values; sliders come in M1)
    private let margin: CGFloat = 0.15
    private let posAlpha: CGFloat = 0.35 // per-60fps-frame easing factor

    private var target: CGPoint?    // view coords, latest detection
    private var displayed: CGPoint? // view coords, eased
    private var hasHand = false
    private var lastSeen: CFTimeInterval = 0
    private var fps: Double = 0

    private let ring = CAShapeLayer()
    private let dot = CALayer()
    private let statusLabel = CATextLayer()
    private var link: CADisplayLink?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        let ringRadius: CGFloat = 18
        ring.path = CGPath(ellipseIn: CGRect(x: -ringRadius, y: -ringRadius,
                                             width: ringRadius * 2, height: ringRadius * 2), transform: nil)
        ring.strokeColor = NSColor.systemTeal.cgColor
        ring.fillColor = NSColor.systemTeal.withAlphaComponent(0.12).cgColor
        ring.lineWidth = 2.5
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.5
        ring.shadowRadius = 4
        ring.shadowOffset = .zero
        ring.opacity = 0

        dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
        dot.cornerRadius = 3.5
        dot.backgroundColor = NSColor.white.cgColor
        ring.addSublayer(dot)

        statusLabel.fontSize = 13
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.foregroundColor = NSColor.white.cgColor
        statusLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        statusLabel.cornerRadius = 6
        statusLabel.alignmentMode = .center
        statusLabel.contentsScale = 2
        statusLabel.frame = CGRect(x: frame.width / 2 - 130, y: 24, width: 260, height: 24)

        layer?.addSublayer(ring)
        layer?.addSublayer(statusLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func removeFromSuperview() {
        link?.invalidate()
        link = nil
        super.removeFromSuperview()
    }

    /// Called on the main queue with each detection result.
    func setDetection(_ frame: LandmarkFrame?) {
        guard let f = frame else {
            hasHand = false
            return
        }
        hasHand = true
        lastSeen = CACurrentMediaTime()
        fps = f.fps
        target = CGPoint(x: remap(f.indexTip.x) * bounds.width,
                         y: remap(f.indexTip.y) * bounds.height)
    }

    /// Edge-margin remap: [margin, 1-margin] stretches to [0, 1], clamped.
    private func remap(_ v: CGFloat) -> CGFloat {
        min(max((v - margin) / (1 - 2 * margin), 0), 1)
    }

    @objc private func step(_ link: CADisplayLink) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let now = CACurrentMediaTime()
        let handFresh = hasHand && (now - lastSeen) < 0.3

        if fps > 0 {
            statusLabel.string = String(format: "AirControl M0 · Detect %.0f fps%@",
                                        fps, handFresh ? "" : " · no hand")
        } else {
            statusLabel.string = "AirControl M0 · show your hand to the camera"
        }

        guard let t = target else { return }
        var d = displayed ?? t
        // Frame-rate-independent easing: posAlpha is defined per 60fps frame.
        let dt = max(link.targetTimestamp - link.timestamp, 1.0 / 240.0)
        let k = 1 - pow(1 - posAlpha, dt * 60)
        d.x += (t.x - d.x) * k
        d.y += (t.y - d.y) * k
        displayed = d

        ring.position = d
        ring.opacity = handFresh ? 1 : 0.25
    }
}
