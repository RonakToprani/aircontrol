import AppKit
import QuartzCore

/// Two borderless, click-through windows covering one screen:
/// - a Space-BOUND content window holding the mock windows, so they behave
///   like real windows — stay on their desktop through a Space switch and
///   never fade (real AX windows inherit this for free in M3);
/// - an all-Spaces HUD window with the AirControl cursor (ring → hover
///   highlight → pinch dot), swipe progress bar, and status line, which
///   follows the user across Spaces and fades during the switch animation.
/// The cursor, drag anchor, and any grabbed window are eased toward their
/// latest targets every render frame via CADisplayLink — the Phase 1
/// two-rate smoothness architecture.
final class OverlayController {
    private var hudWindow: NSWindow?
    private var contentWindow: NSWindow?
    private let view: OverlayView
    private var spaceObserver: NSObjectProtocol?

    init(screen: NSScreen, configProvider: @escaping () -> Config, mover: WindowMover) {
        func makeWindow(_ contentView: NSView, allSpaces: Bool) -> NSWindow {
            let w = NSWindow(contentRect: screen.frame,
                             styleMask: .borderless,
                             backing: .buffered,
                             defer: false)
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.backgroundColor = .clear
            w.isOpaque = false
            w.hasShadow = false
            w.collectionBehavior = allSpaces
                ? [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
                : [.stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.contentView = contentView
            return w
        }

        let mockHostView = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        mockHostView.wantsLayer = true
        contentWindow = makeWindow(mockHostView, allSpaces: false)

        view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                           configProvider: configProvider,
                           mockHost: mockHostView.layer!,
                           mover: mover)
        hudWindow = makeWindow(view, allSpaces: true)

        // Fade the HUD only when a Space switch actually happens (whatever
        // triggered it) — a swipe that fires on the last Space switches
        // nothing and must not blank the pointer.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak view] _ in view?.noteSpaceChange() }
    }

    func show() {
        contentWindow?.orderFrontRegardless()
        hudWindow?.orderFrontRegardless() // after content, so the HUD draws on top
    }

    func close() {
        if let o = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            spaceObserver = nil
        }
        hudWindow?.orderOut(nil)
        hudWindow = nil
        contentWindow?.orderOut(nil)
        contentWindow = nil
    }

    func update(state: GestureState) { view.apply(state) }
}

// MARK: -

private final class MockWindowLayer: CALayer {
    var center: CGPoint = .zero { didSet { position = center } }
    var target: CGPoint = .zero

    init(title: String, size: CGSize, tint: NSColor) {
        super.init()
        bounds = CGRect(origin: .zero, size: size)
        backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 0.92).cgColor
        cornerRadius = 10
        borderWidth = 1.5
        borderColor = NSColor(calibratedWhite: 1, alpha: 0.15).cgColor
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.35
        shadowRadius = 10
        shadowOffset = CGSize(width: 0, height: -4)

        let titleBar = CALayer()
        titleBar.frame = CGRect(x: 0, y: size.height - 30, width: size.width, height: 30)
        titleBar.backgroundColor = tint.withAlphaComponent(0.25).cgColor
        titleBar.cornerRadius = 10
        titleBar.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        addSublayer(titleBar)

        let label = CATextLayer()
        label.string = title
        label.fontSize = 13
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.foregroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        label.alignmentMode = .center
        label.contentsScale = 2
        label.frame = CGRect(x: 0, y: size.height - 26, width: size.width, height: 20)
        addSublayer(label)
    }

    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func containsInSuperlayer(_ p: CGPoint) -> Bool {
        frame.contains(p)
    }

    func setLook(hovered: Bool, grabbed: Bool) {
        if grabbed {
            borderColor = NSColor.systemTeal.cgColor
            borderWidth = 2.5
            shadowOpacity = 0.65
            shadowRadius = 22
        } else if hovered {
            borderColor = NSColor.systemTeal.withAlphaComponent(0.7).cgColor
            borderWidth = 2
            shadowOpacity = 0.35
            shadowRadius = 10
        } else {
            borderColor = NSColor(calibratedWhite: 1, alpha: 0.15).cgColor
            borderWidth = 1.5
            shadowOpacity = 0.35
            shadowRadius = 10
        }
    }
}

// MARK: -

final class OverlayView: NSView {
    private let configProvider: () -> Config
    private let mockHost: CALayer // the Space-bound content window's layer
    private let mover: WindowMover

    // Latest state from the gesture engine (detection rate).
    private var state = GestureState()
    private var lastSeen: CFTimeInterval = 0
    private var pointerTarget: CGPoint?
    private var anchorTarget: CGPoint?

    // Eased display positions (render rate).
    private var pointer: CGPoint?
    private var anchor: CGPoint?

    // Drag state (mock windows).
    private var grabbed: MockWindowLayer?
    private var grabOffset: CGPoint = .zero
    private var wasPinching = false

    // Drag state (real windows, M3). Frames in CG coords (top-left origin).
    private var hoveredTarget: TargetWindow?
    private var latestHover: TargetWindow?
    private var lastHoverQuery: CFTimeInterval = 0
    private var grabbedTarget: TargetWindow?
    private var grabOffsetCG: CGPoint = .zero
    private var lastDragOrigin: CGPoint?
    private let ghost = CAShapeLayer()

    // Layers.
    private var mockWindows: [MockWindowLayer] = []
    private let ring = CAShapeLayer()
    private let dot = CALayer()
    private let swipeBarBack = CALayer()
    private let swipeBarFill = CALayer()
    private let swipeFlash = CATextLayer()
    private var swipeFlashTime: CFTimeInterval = -1e9
    private var spaceChangeTime: CFTimeInterval = -1e9
    private let statusLabel = CATextLayer()
    private var link: CADisplayLink?

    private let ringRadius: CGFloat = 18

    init(frame: NSRect, configProvider: @escaping () -> Config, mockHost: CALayer, mover: WindowMover) {
        self.configProvider = configProvider
        self.mockHost = mockHost
        self.mover = mover
        super.init(frame: frame)
        wantsLayer = true

        ghost.opacity = 0
        ghost.strokeColor = NSColor.systemTeal.cgColor
        ghost.fillColor = NSColor.clear.cgColor
        ghost.lineWidth = 2
        layer?.addSublayer(ghost)

        let notes = MockWindowLayer(title: "Mock window A", size: CGSize(width: 380, height: 250), tint: .systemTeal)
        notes.center = CGPoint(x: frame.width * 0.3, y: frame.height * 0.55)
        notes.target = notes.center
        let browser = MockWindowLayer(title: "Mock window B", size: CGSize(width: 420, height: 280), tint: .systemOrange)
        browser.center = CGPoint(x: frame.width * 0.68, y: frame.height * 0.42)
        browser.target = browser.center
        mockWindows = [notes, browser]
        mockWindows.forEach { mockHost.addSublayer($0) }

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

        swipeBarBack.bounds = CGRect(x: 0, y: 0, width: 64, height: 6)
        swipeBarBack.cornerRadius = 3
        swipeBarBack.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor
        swipeBarBack.opacity = 0
        swipeBarFill.bounds = CGRect(x: 0, y: 0, width: 0, height: 6)
        swipeBarFill.cornerRadius = 3
        swipeBarFill.backgroundColor = NSColor.systemGreen.cgColor
        swipeBarFill.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        swipeBarBack.addSublayer(swipeBarFill)

        swipeFlash.fontSize = 34
        swipeFlash.font = NSFont.systemFont(ofSize: 34, weight: .bold)
        swipeFlash.foregroundColor = NSColor.systemGreen.cgColor
        swipeFlash.alignmentMode = .center
        swipeFlash.contentsScale = 2
        swipeFlash.frame = CGRect(x: frame.width / 2 - 150, y: frame.height - 120, width: 300, height: 44)
        swipeFlash.opacity = 0

        statusLabel.fontSize = 13
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.foregroundColor = NSColor.white.cgColor
        statusLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        statusLabel.cornerRadius = 6
        statusLabel.alignmentMode = .center
        statusLabel.contentsScale = 2
        statusLabel.frame = CGRect(x: frame.width / 2 - 190, y: 24, width: 380, height: 24)

        [ring, swipeBarBack, swipeFlash, statusLabel].forEach { layer?.addSublayer($0) }
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

    func noteSpaceChange() {
        spaceChangeTime = CACurrentMediaTime()
        // The old Space's windows are gone from under the pointer — drop any
        // hover target so its outline can't linger on the new Space.
        hoveredTarget = nil
        latestHover = nil
        ghost.opacity = 0
    }

    /// Called on the main queue at detection rate with the engine's output.
    func apply(_ s: GestureState) {
        state = s
        guard s.handVisible else { return }
        lastSeen = CACurrentMediaTime()
        pointerTarget = CGPoint(x: s.pointer.x * bounds.width, y: s.pointer.y * bounds.height)
        anchorTarget = CGPoint(x: s.anchor.x * bounds.width, y: s.anchor.y * bounds.height)
        if let event = s.swipeEvent {
            swipeFlashTime = CACurrentMediaTime()
            let dir = configProvider().swipeNatural ? -event : event
            swipeFlash.string = dir > 0 ? "Space  ⟶" : "⟵  Space"
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let config = configProvider()
        let now = CACurrentMediaTime()
        let handFresh = state.handVisible && (now - lastSeen) < 0.3

        // Hide the HUD while a Space switch animates — anything drawn during
        // the slide reads as chop. Keyed to the real activeSpaceDidChange
        // notification, not the swipe gesture. Quick ease out, gentler ease in.
        let switching = (now - spaceChangeTime) < config.postSwipeSettleMS / 1000
        if let w = window {
            let target: CGFloat = switching ? 0 : 1
            w.alphaValue += (target - w.alphaValue) * (switching ? 0.35 : 0.15)
        }

        // Frame-rate-independent easing (posAlpha defined per 60fps frame).
        let dt = max(link.targetTimestamp - link.timestamp, 1.0 / 240.0)
        let k = 1 - pow(1 - CGFloat(config.posAlpha), CGFloat(dt * 60))

        if let t = pointerTarget {
            var p = pointer ?? t
            p.x += (t.x - p.x) * k
            p.y += (t.y - p.y) * k
            pointer = p
        }
        if let t = anchorTarget {
            var a = anchor ?? t
            a.x += (t.x - a.x) * k
            a.y += (t.y - a.y) * k
            anchor = a
        }

        // --- Grab / drag (knuckle-driven, so the pinch curl doesn't lurch it).
        let mocksOn = config.useMockWindows
        mockHost.isHidden = !mocksOn
        let hoverActive: Bool

        if mocksOn {
            ghost.opacity = 0
            if state.pinching, !wasPinching, handFresh, let p = pointer, let a = anchor {
                if let win = mockWindows.last(where: { $0.containsInSuperlayer(p) }) {
                    grabbed = win
                    grabOffset = CGPoint(x: win.center.x - a.x, y: win.center.y - a.y)
                    mockWindows.removeAll { $0 === win } // move to top
                    mockWindows.append(win)
                    mockHost.addSublayer(win) // HUD lives in its own window above
                }
            }
            if !state.pinching { grabbed = nil }

            if let win = grabbed, let a = anchor {
                win.target = CGPoint(x: a.x + grabOffset.x, y: a.y + grabOffset.y)
            }
            for win in mockWindows {
                var c = win.center
                c.x += (win.target.x - c.x) * k
                c.y += (win.target.y - c.y) * k
                win.center = c
            }
            let hovered = (handFresh && grabbed == nil && pointer != nil)
                ? mockWindows.last(where: { $0.containsInSuperlayer(pointer!) }) : nil
            for win in mockWindows {
                win.setLook(hovered: win === hovered, grabbed: win === grabbed)
            }
            hoverActive = hovered != nil
        } else {
            grabbed = nil
            stepRealWindows(config: config, now: now, handFresh: handFresh)
            hoverActive = hoveredTarget != nil
        }
        wasPinching = state.pinching

        if let p = pointer {
            ring.position = p
            ring.opacity = handFresh ? (state.settling ? 0.35 : 1) : 0.25
            if state.pinching {
                ring.fillColor = NSColor.systemTeal.withAlphaComponent(0.85).cgColor
                ring.transform = CATransform3DMakeScale(0.65, 0.65, 1)
            } else {
                ring.fillColor = NSColor.systemTeal.withAlphaComponent(hoverActive ? 0.3 : 0.12).cgColor
                ring.transform = CATransform3DIdentity
            }
        }

        // --- Swipe progress bar above the cursor.
        stepSwipeUI(now: now, handFresh: handFresh)
    }

    /// Real-window hover / grab / drag (M3). All frames in CG coords; the
    /// ghost outline is the 60fps feedback while AX writes trail at whatever
    /// rate the target app absorbs.
    private func stepRealWindows(config: Config, now: CFTimeInterval, handFresh: Bool) {
        if state.settling {
            hoveredTarget = nil
            latestHover = nil
        }
        // Hover: throttled async window-under-pointer query + sticky targeting
        // (once targeted, a window keeps the target until the pointer clearly
        // exits its frame — jitter can never flick the target at grab time).
        if grabbedTarget == nil, handFresh, !state.settling, let p = pointer {
            if now - lastHoverQuery > 0.12 {
                lastHoverQuery = now
                mover.queryWindow(at: cgPoint(fromView: p)) { [weak self] t in
                    self?.latestHover = t
                }
            }
            let pCG = cgPoint(fromView: p)
            if let hov = hoveredTarget {
                let m = CGFloat(config.stickyHoverPx)
                if !hov.frame.insetBy(dx: -m, dy: -m).contains(pCG) {
                    hoveredTarget = latestHover
                } else if let fresh = latestHover, fresh.windowID == hov.windowID {
                    hoveredTarget = fresh // same window — refresh its frame
                }
            } else {
                hoveredTarget = latestHover
            }
        } else if !handFresh {
            hoveredTarget = nil
            latestHover = nil
        }

        // Grab on the pinch edge; drag from the eased knuckle anchor.
        if state.pinching, !wasPinching, handFresh, let t = hoveredTarget, let a = anchor {
            grabbedTarget = t
            let aCG = cgPoint(fromView: a)
            grabOffsetCG = CGPoint(x: t.frame.origin.x - aCG.x, y: t.frame.origin.y - aCG.y)
            lastDragOrigin = t.frame.origin
            mover.beginDrag(t)
        }
        if !state.pinching, grabbedTarget != nil {
            mover.endDrag(at: lastDragOrigin) // window commits where dropped
            grabbedTarget = nil
        }
        if let t = grabbedTarget, let a = anchor {
            let aCG = cgPoint(fromView: a)
            let origin = CGPoint(x: aCG.x + grabOffsetCG.x, y: aCG.y + grabOffsetCG.y)
            lastDragOrigin = origin
            mover.drag(to: origin)
            drawGhost(viewRect(fromCG: CGRect(origin: origin, size: t.frame.size)), strong: true)
        } else if let h = hoveredTarget, handFresh {
            drawGhost(viewRect(fromCG: h.frame), strong: false)
        } else {
            ghost.opacity = 0
        }
    }

    private func drawGhost(_ r: CGRect, strong: Bool) {
        ghost.frame = r
        ghost.path = CGPath(roundedRect: CGRect(origin: .zero, size: r.size),
                            cornerWidth: 10, cornerHeight: 10, transform: nil)
        ghost.lineWidth = strong ? 2.5 : 1.5
        ghost.strokeColor = NSColor.systemTeal.withAlphaComponent(strong ? 0.9 : 0.55).cgColor
        ghost.fillColor = strong ? NSColor.systemTeal.withAlphaComponent(0.07).cgColor
                                 : NSColor.clear.cgColor
        ghost.opacity = 1
    }

    /// AppKit-global ↔ CG (top-left-origin) conversions, anchored on the
    /// primary display's height. The view fills its screen exactly.
    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func cgPoint(fromView p: CGPoint) -> CGPoint {
        guard let wf = window?.frame else { return .zero }
        return CGPoint(x: wf.origin.x + p.x, y: primaryHeight - (wf.origin.y + p.y))
    }

    private func viewRect(fromCG r: CGRect) -> CGRect {
        guard let wf = window?.frame else { return .zero }
        return CGRect(x: r.minX - wf.origin.x,
                      y: (primaryHeight - r.maxY) - wf.origin.y,
                      width: r.width, height: r.height)
    }

    private func stepSwipeUI(now: CFTimeInterval, handFresh: Bool) {
        if let p = pointer, handFresh, state.swiping, abs(state.swipeProgress) > 0.02 {
            swipeBarBack.position = CGPoint(x: p.x, y: p.y + ringRadius + 18)
            swipeBarBack.opacity = 1
            let w = CGFloat(abs(state.swipeProgress)) * 64
            swipeBarFill.bounds = CGRect(x: 0, y: 0, width: w, height: 6)
            swipeBarFill.position = CGPoint(x: 32, y: 3)
        } else {
            swipeBarBack.opacity = 0
        }

        // --- Swipe flash fade.
        swipeFlash.opacity = Float(max(0, 1 - (now - swipeFlashTime) / 0.8))

        // --- Status line.
        if state.fps > 0 {
            let gesture = state.pinching ? "PINCH"
                : state.swiping ? (state.swipeArmed ? "PALM ✓ armed" : "PALM — hold still to arm")
                : "point"
            statusLabel.string = String(format: "AirControl M3 · %.0f fps · %@%@",
                                        state.fps, gesture, handFresh ? "" : " · no hand")
        } else {
            statusLabel.string = "AirControl M3 · show your hand to the camera"
        }
    }
}
