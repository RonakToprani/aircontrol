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

        // M2: the HUD follows the mapper's active display — in Model B the
        // pointer only ever exists on one display at a time, so one window
        // that relocates is exactly the right shape. Mocks stay put.
        view.onActiveScreenChange = { [weak self] screen in
            guard let self, let w = self.hudWindow else { return }
            w.setFrame(screen.frame, display: true)
            self.view.relayoutStatics()
        }

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
        view.prepareForClose() // release a held synthetic mouse button
        hudWindow?.orderOut(nil)
        hudWindow = nil
        contentWindow?.orderOut(nil)
        contentWindow = nil
    }

    func update(state: GestureState) { view.apply(state) }

    /// The AirControl pointer's current global position in CG coords —
    /// where a Space switch should be targeted.
    func pointerCG() -> CGPoint? { view.currentPointerCG() }

    /// Overrides the status line (calibration instructions etc.); nil clears.
    func setPrompt(_ text: String?) { view.prompt = text }

    /// Clears the prompt only if it still shows `text` — an old timer must
    /// never wipe a prompt some later flow (calibration, another notice)
    /// has since put up.
    func clearPrompt(ifMatches text: String) {
        if view.prompt == text { view.prompt = nil }
    }
}

extension Notification.Name {
    /// A practice (mock) window was pinch-dragged a real distance — the
    /// welcome tour's grab drill completes on this.
    static let aircontrolMockWindowDragged = Notification.Name("aircontrol.mockWindowDragged")
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

    // MARK: scrollable practice content

    private var stripes: CALayer?
    private var stripesBaseY: CGFloat = 0
    private var scrollPhase: CGFloat = 0
    private let stripePitch: CGFloat = 34
    var scrollable: Bool { stripes != nil }

    /// Fake document rows inside the window body — the tour's scroll drill
    /// moves these instead of any real content, wrapping seamlessly so the
    /// "page" never runs out.
    func addScrollContent() {
        let clip = CALayer()
        clip.frame = CGRect(x: 1.5, y: 1.5, width: bounds.width - 3, height: bounds.height - 33)
        clip.masksToBounds = true
        clip.cornerRadius = 9
        let content = CALayer()
        content.frame = clip.bounds
        // The wrap period is the PATTERN period — three rows of varying
        // length (see scrollContent) — so rows must overhang the clip by a
        // full period on both sides for the wrap snap to land on an
        // identical-looking frame.
        let rows = Int(clip.bounds.height / stripePitch) + 4
        for i in -4..<rows {
            let row = CALayer()
            let trim = CGFloat(((i % 3) + 3) % 3) * 44 // varied lengths read as text
            row.frame = CGRect(x: 16, y: CGFloat(i) * stripePitch + 8,
                               width: clip.bounds.width - 32 - trim, height: 16)
            row.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
            row.cornerRadius = 5
            content.addSublayer(row)
        }
        clip.addSublayer(content)
        addSublayer(clip)
        stripes = content
        stripesBaseY = content.position.y
    }

    /// wheel-pixel delta in, wrapped row motion out. Wraps on the pattern
    /// period (three rows — the trim cycle in addScrollContent), not a single
    /// row pitch: wrapping every 34px put differently-trimmed rows where
    /// their neighbors just were, visibly teleporting row lengths.
    func scrollContent(byWheel dy: CGFloat) {
        guard let content = stripes else { return }
        scrollPhase = (scrollPhase + dy).truncatingRemainder(dividingBy: stripePitch * 3)
        content.position.y = stripesBaseY - scrollPhase
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
    private let mapper = PointerMapper()
    private let mouse = MouseController()
    var onActiveScreenChange: ((NSScreen) -> Void)?

    // Latest state from the gesture engine (detection rate).
    private var state = GestureState()
    private var lastSeen: CFTimeInterval = 0
    private var pointerTarget: CGPoint?
    private var anchorTarget: CGPoint?

    // Eased display positions (render rate).
    private var pointer: CGPoint?
    private var anchor: CGPoint?

    // Scroll grab (mouse mode): the pointer mapping freezes (mapper hold)
    // while this eased shadow follows the UNCLAMPED hand position — its
    // per-frame delta becomes wheel pixels even past the calibration box,
    // and its velocity carries the momentum tail after release.
    private var scrollNormTarget: CGPoint = .zero
    private var scrollEased: CGPoint?
    private var scrollVel = CGVector.zero
    private var lastScrollSandbox = false

    // Dictation (mouse mode): pinch-hold still on a text field turns the
    // pinch into a push-to-talk button.
    private let speech = SpeechController()
    private var dictating = false
    private var pinchStart: CFTimeInterval = -1e9
    private var dictationDisplay: String? // HUD transcript line while live

    // Drag state (mock windows).
    private var grabbed: MockWindowLayer?
    private var grabOffset: CGPoint = .zero
    private var grabStartCenter: CGPoint?
    private var mockDragNotified = false
    private var wasPinching = false

    // Grab arming: a pinch means "grab" only after it has survived grabArmMS
    // — a hand closing into a fist (or fingers just curling) passes through
    // the pinch shape, and in gesture mode there is no deferred mouse-down
    // to save us. One pinch gets one grab attempt (grabSpent), so a pinch
    // begun over nothing can't snatch a window it drifts across mid-hold.
    private var pinchBegan: CFTimeInterval = -1e9
    private var grabSpent = false
    /// How long past the arm a pinch keeps waiting for the async hover query
    /// to land before it's spent — covers a pinch thrown right as the pointer
    /// arrives on a window (the old edge-triggered grab just missed those).
    private let grabAcquireCap: CFTimeInterval = 0.35

    // Drag state (real windows, M3). Frames in CG coords (top-left origin).
    private var hoveredTarget: TargetWindow?
    private var latestHover: TargetWindow?
    private var lastHoverQuery: CFTimeInterval = 0
    private var hoverExitSince: CFTimeInterval?
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
    var prompt: String? // overrides the status line while set

    // M2 seam-crossing UI.
    private var seamPressure: Double = 0
    private var seamDX = 0
    private var seamDY = 0
    private let seamBarBack = CALayer()
    private let seamBarFill = CALayer()
    private let glow = CALayer()
    private let statusLabel = CATextLayer()
    private var lastStatusText = ""
    private var link: CADisplayLink?
    // Tracks the frame-rate range last applied to the link, so a default-off
    // launch never touches it at all — identical to pre-lightweight behavior.
    private var linkLightweight = false

    private let ringRadius: CGFloat = 18

    init(frame: NSRect, configProvider: @escaping () -> Config, mockHost: CALayer, mover: WindowMover) {
        self.configProvider = configProvider
        self.mockHost = mockHost
        self.mover = mover
        super.init(frame: frame)
        wantsLayer = true
        // The practice windows are not merely hidden at launch — they don't
        // EXIST until the first frame that wants them (ensureMockWindows).
        // A hide can race the first render tick and flash; absence can't.
        mockHost.isHidden = true

        glow.borderColor = NSColor.systemTeal.withAlphaComponent(0.18).cgColor
        glow.borderWidth = 3
        glow.frame = NSRect(origin: .zero, size: frame.size)
        layer?.addSublayer(glow)

        ghost.opacity = 0
        ghost.strokeColor = NSColor.systemTeal.cgColor
        ghost.fillColor = NSColor.clear.cgColor
        ghost.lineWidth = 2
        layer?.addSublayer(ghost)

        seamBarBack.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.18).cgColor
        seamBarBack.cornerRadius = 3
        seamBarBack.opacity = 0
        seamBarFill.backgroundColor = NSColor.systemTeal.cgColor
        seamBarFill.cornerRadius = 3
        seamBarFill.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        seamBarBack.addSublayer(seamBarFill)
        layer?.addSublayer(seamBarBack)


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

    /// Builds the two practice windows on the first frame that wants them.
    /// Deliberately NOT done in init: layers that never exist before practice
    /// can never flash at launch, whatever the render loop's timing does.
    private func ensureMockWindows() {
        let notes = MockWindowLayer(title: "Practice window", size: CGSize(width: 380, height: 250), tint: .systemTeal)
        notes.center = CGPoint(x: bounds.width * 0.3, y: bounds.height * 0.55)
        notes.target = notes.center
        let browser = MockWindowLayer(title: "Scroll practice", size: CGSize(width: 420, height: 280), tint: .systemOrange)
        browser.center = CGPoint(x: bounds.width * 0.68, y: bounds.height * 0.42)
        browser.target = browser.center
        browser.addScrollContent()
        mockWindows = [notes, browser]
        mockWindows.forEach { mockHost.addSublayer($0) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, link == nil else { return }
        let l = displayLink(target: self, selector: #selector(step(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func removeFromSuperview() {
        prepareForClose()
        super.removeFromSuperview()
    }

    func prepareForClose() {
        if dictating { abortDictation() }
        mouse.releaseIfNeeded()
        mouse.setCursorHidden(false)
        link?.invalidate()
        link = nil
    }

    func currentPointerCG() -> CGPoint? {
        guard let p = pointer else { return nil }
        return cgPoint(fromView: p)
    }

    func noteSpaceChange() {
        spaceChangeTime = CACurrentMediaTime()
        // The old Space's windows are gone from under the pointer — drop any
        // hover target so its outline can't linger on the new Space.
        hoveredTarget = nil
        latestHover = nil
        hoverExitSince = nil
        ghost.opacity = 0
    }

    /// Called on the main queue at detection rate with the engine's output.
    func apply(_ s: GestureState) {
        state = s
        guard s.handVisible else { return }
        lastSeen = CACurrentMediaTime()
        let m = mapper.map(pointerNorm: s.pointer, anchorNorm: s.anchor, pinching: s.pinching,
                           hold: s.pointerHeld || dictating, config: configProvider(), now: lastSeen)
        scrollNormTarget = s.scrollPoint
        if m.screenChanged {
            onActiveScreenChange?(m.screen)
            pointer = nil // re-seed eased positions in the new window's coords
            anchor = nil
        }
        let origin = window?.frame.origin ?? .zero
        pointerTarget = CGPoint(x: m.pointer.x - origin.x, y: m.pointer.y - origin.y)
        anchorTarget = CGPoint(x: m.anchor.x - origin.x, y: m.anchor.y - origin.y)
        seamPressure = m.pressure
        seamDX = m.pressureDX
        seamDY = m.pressureDY
        // Only flash "Space ⟶" when a switch can actually happen — with
        // switching suppressed (practice sandbox, or the tuning toggle off)
        // the banner would announce a switch that never occurs.
        if let event = s.swipeEvent, configProvider().switchSpaces {
            swipeFlashTime = CACurrentMediaTime()
            swipeFlash.foregroundColor = NSColor.systemGreen.cgColor
            let dir = configProvider().swipeNatural ? -event : event
            swipeFlash.string = dir > 0 ? "Space  ⟶" : "⟵  Space"
        }
        if s.shakaEvent { // AppState toggled the mode before handing us this
            let c = configProvider()
            // Pre-practice tour (and the post-close countdown) suppress the
            // shaka TOGGLE in AppState — flashing MOUSE ON/OFF here would
            // announce a switch that didn't happen. Practice shows it: the
            // drill's feedback is exactly this flash.
            if !c.tourSandbox || c.useMockWindows {
                swipeFlashTime = CACurrentMediaTime()
                swipeFlash.foregroundColor = NSColor.systemIndigo.cgColor
                swipeFlash.string = c.mouseMode ? "🤙  MOUSE ON" : "🤙  MOUSE OFF"
            }
        }
        // 👍 fired (once per engine frame — handled here, not in step, so a
        // render frame can never see it twice and double-press Return).
        // Never in the sandbox (tour-wide or practice): a REAL Return
        // keypress would leak out of "nothing real is touched" into
        // whatever field has focus.
        if s.sendEvent {
            let c = configProvider()
            if !c.useMockWindows, !c.tourSandbox {
                mouse.pressReturnIfTextHasContent()
                swipeFlashTime = CACurrentMediaTime()
                swipeFlash.foregroundColor = NSColor.systemGreen.cgColor
                swipeFlash.string = "👍  ⏎"
            }
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let config = configProvider()
        let now = CACurrentMediaTime()
        let handFresh = state.handVisible && (now - lastSeen) < 0.3

        // Lightweight: cap this full layer pass at ≤60fps — a ProMotion
        // display otherwise runs it at 120Hz for no visible gain. min 30 lets
        // the system drop further under load. Easing below is already
        // dt-scaled, so motion feel survives any rate the link settles on.
        if config.lightweight != linkLightweight {
            linkLightweight = config.lightweight
            link.preferredFrameRateRange = config.lightweight
                ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                : .default
        }

        // One clock for "how long has this pinch been held" — the grab paths
        // arm on it. A fresh pinch also unthrottles the hover query so the
        // window under the pointer is known by the time the grab arms.
        if state.pinching, !wasPinching {
            pinchBegan = now
            grabSpent = false
            lastHoverQuery = -1e9
        }

        // Hide the HUD while a Space switch animates — anything drawn during
        // the slide reads as chop. Keyed to the real activeSpaceDidChange
        // notification, not the swipe gesture. Quick ease out, gentler ease in.
        let switching = (now - spaceChangeTime) < config.postSwipeSettleMS / 1000
        if let w = window {
            let target: CGFloat = switching ? 0 : 1
            let a = w.alphaValue
            if abs(target - a) > 0.001 {
                w.alphaValue = a + (target - a) * (switching ? 0.35 : 0.15)
            } else if a != target {
                // Snap the last sliver, then stop: alphaValue writes reach the
                // window server, and steady state was re-writing 1.0 forever.
                w.alphaValue = target
            }
        }

        // Frame-rate-independent easing (posAlpha defined per 60fps frame).
        let dt = max(link.targetTimestamp - link.timestamp, 1.0 / 240.0)
        let k = 1 - pow(1 - CGFloat(config.posAlpha), CGFloat(dt * 60))

        // While scroll-grabbing (and through the clutch), the mapper holds
        // the pointer target frozen — easing just keeps the ring settled.
        let scrollHold = config.mouseMode && state.scrollGrab && handFresh
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

        // --- Mouse mode: the eased pointer drives the REAL cursor; pinch is
        // the left button. Grab/hover is suspended — pinch must mean exactly
        // one thing, and pinch-dragging a title bar moves windows natively.
        // With the sandbox on — the whole welcome tour, or the practice
        // toggle — mouse mode goes VISUAL-ONLY: no CGEvents post, the system
        // cursor stays put, the fist scrolls the practice pane — the tour
        // can teach without touching anything real.
        let sandbox = config.useMockWindows || config.tourSandbox
        if config.mouseMode, sandbox {
            mouse.setCursorHidden(false)
            mouse.releaseIfNeeded()
            if dictating { abortDictation() }
            stepScroll(config: config, dt: dt, k: k,
                       active: scrollHold && !state.settling)
        } else if config.mouseMode {
            mouse.dragSlopPx = CGFloat(config.mouseDragSlopPx)
            mouse.downDelay = config.mouseDownDelayMS / 1000
            mouse.setCursorHidden(config.hideSystemCursor)
            mouse.reassertCursorHide(now: now)
            if handFresh, !state.settling, let p = pointer {
                let pCG = cgPoint(fromView: p)
                if state.scrollGrab {
                    mouse.cancelPending() // the "pinch" was this fist closing
                    mouse.releaseIfNeeded(at: pCG) // a committed down never sticks
                } else {
                    if state.pinching, !wasPinching {
                        pinchStart = now
                        mouse.pinchDown(at: pCG, now: now,
                                        openQuery: config.pinchOpensFiles,
                                        textQuery: config.dictation)
                    }
                    if !state.pinching {
                        if dictating {
                            endDictation()
                        } else {
                            mouse.pinchUp(at: pCG)
                        }
                    }
                    // Pinch held still on a text field past the threshold:
                    // the click completes (field focused, caret placed) and
                    // the pinch becomes the push-to-talk button.
                    if config.dictation, state.pinching, !dictating,
                       !mouse.dragging, mouse.textTarget,
                       now - pinchStart >= config.dictateHoldMS / 1000 {
                        beginDictation()
                    }
                    if !dictating {
                        mouse.commitPending(now: now)
                        mouse.move(to: pCG)
                    }
                }
            } else {
                mouse.releaseIfNeeded(at: pointer.map(cgPoint(fromView:)))
            }
            stepScroll(config: config, dt: dt, k: k, active: scrollHold && !state.settling)
        } else {
            mouse.setCursorHidden(false)
            mouse.releaseIfNeeded()
            scrollEased = nil
            scrollVel = .zero
            if dictating { abortDictation() }
        }

        // --- Grab / drag (knuckle-driven, so the pinch curl doesn't lurch it).
        // The practice windows work in BOTH modes — during practice a pinch
        // always grabs something safe, never a real window. They appear only
        // when the mock toggle is on (the tour forces it just for practice);
        // the rest of the tour is sandboxed WITHOUT them.
        let mocksOn = config.useMockWindows
        if mocksOn, mockWindows.isEmpty { ensureMockWindows() }
        mockHost.isHidden = !mocksOn
        let hoverActive: Bool

        if config.mouseMode, !mocksOn {
            grabbed = nil
            if grabbedTarget != nil { // mode flipped mid-AX-drag: drop in place
                mover.endDrag(at: lastDragOrigin)
                grabbedTarget = nil
            }
            hoveredTarget = nil
            latestHover = nil
            ghost.opacity = 0
            hoverActive = false
        } else if mocksOn {
            if grabbedTarget != nil { // entering the sandbox mid-AX-drag
                mover.endDrag(at: lastDragOrigin)
                grabbedTarget = nil
            }
            hoveredTarget = nil
            latestHover = nil
            ghost.opacity = 0
            // Armed, not edge-triggered — same reasoning as the real-window
            // grab: a transitional pinch never lives grabArmMS.
            if state.pinching, !grabSpent, grabbed == nil, handFresh,
               now - pinchBegan >= config.grabArmMS / 1000,
               let p = pointer, let a = anchor {
                grabSpent = true // containment is synchronous — hit or miss, this pinch is decided
                if let win = mockWindows.last(where: { $0.containsInSuperlayer(p) }) {
                    grabbed = win
                    grabStartCenter = win.center
                    mockDragNotified = false
                    grabOffset = CGPoint(x: win.center.x - a.x, y: win.center.y - a.y)
                    mockWindows.removeAll { $0 === win } // move to top
                    mockWindows.append(win)
                    mockHost.addSublayer(win) // HUD lives in its own window above
                }
            }
            if !state.pinching { grabbed = nil }

            if let win = grabbed, let a = anchor {
                win.target = CGPoint(x: a.x + grabOffset.x, y: a.y + grabOffset.y)
                // The welcome tour's grab drill listens for a real drag —
                // fired once per grab, only after honest travel.
                if !mockDragNotified, let s = grabStartCenter,
                   hypot(win.target.x - s.x, win.target.y - s.y) > 60 {
                    mockDragNotified = true
                    NotificationCenter.default.post(name: .aircontrolMockWindowDragged, object: nil)
                }
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
        } else if config.tourSandbox {
            // Tour open, practice windows not up yet (the "raise your hand"
            // and permission steps): the pointer gives feedback, but no real
            // window may be hovered or grabbed.
            grabbed = nil
            if grabbedTarget != nil { // tour opened mid-AX-drag: drop in place
                mover.endDrag(at: lastDragOrigin)
                grabbedTarget = nil
            }
            hoveredTarget = nil
            latestHover = nil
            ghost.opacity = 0
            hoverActive = false
        } else {
            grabbed = nil
            stepRealWindows(config: config, now: now, handFresh: handFresh)
            hoverActive = hoveredTarget != nil
        }
        wasPinching = state.pinching

        if let p = pointer {
            ring.position = p
            ring.opacity = handFresh ? (state.settling ? 0.35 : 1) : 0.25
            if dictating {
                // Push-to-talk live: unmistakably NOT a click.
                ring.fillColor = NSColor.systemOrange.withAlphaComponent(0.8).cgColor
                ring.transform = CATransform3DMakeScale(0.8, 0.8, 1)
            } else if state.pinching {
                ring.fillColor = NSColor.systemTeal.withAlphaComponent(0.85).cgColor
                ring.transform = CATransform3DMakeScale(0.65, 0.65, 1)
            } else if config.mouseMode, state.scrollGrab {
                ring.fillColor = NSColor.systemIndigo.withAlphaComponent(0.5).cgColor
                ring.transform = CATransform3DMakeScale(0.8, 0.8, 1)
            } else {
                ring.fillColor = NSColor.systemTeal.withAlphaComponent(hoverActive ? 0.3 : 0.12).cgColor
                ring.transform = CATransform3DIdentity
            }
        }

        // --- Seam pressure meter (M2): shows crossing progress at the edge
        // being pushed, at the pointer's height — deliberate push fills it,
        // casual pointing near the edge barely registers.
        if seamPressure > 0.02, handFresh, let p = pointer {
            seamBarBack.opacity = 1
            let len: CGFloat = 64
            if seamDX != 0 {
                seamBarBack.bounds = CGRect(x: 0, y: 0, width: 6, height: len)
                seamBarBack.position = CGPoint(x: seamDX > 0 ? bounds.width - 10 : 10,
                                               y: min(max(p.y, len / 2), bounds.height - len / 2))
                seamBarFill.bounds = CGRect(x: 0, y: 0, width: 6, height: len * CGFloat(seamPressure))
                seamBarFill.position = CGPoint(x: 3, y: len / 2)
            } else {
                seamBarBack.bounds = CGRect(x: 0, y: 0, width: len, height: 6)
                seamBarBack.position = CGPoint(x: min(max(p.x, len / 2), bounds.width - len / 2),
                                               y: seamDY > 0 ? bounds.height - 10 : 10)
                seamBarFill.bounds = CGRect(x: 0, y: 0, width: len * CGFloat(seamPressure), height: 6)
                seamBarFill.position = CGPoint(x: len / 2, y: 3)
            }
        } else {
            seamBarBack.opacity = 0
        }

        // --- Swipe progress bar above the cursor.
        stepSwipeUI(now: now, handFresh: handFresh)
    }

    /// Reposition fixed HUD furniture after the window relocates to a display
    /// with a different size.
    func relayoutStatics() {
        let size = window?.frame.size ?? bounds.size
        setFrameSize(size)
        glow.frame = CGRect(origin: .zero, size: size)
        swipeFlash.frame = CGRect(x: size.width / 2 - 150, y: size.height - 120, width: 300, height: 44)
        statusLabel.frame = CGRect(x: size.width / 2 - 190, y: 24, width: 380, height: 24)
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
                    // Clearly outside — but only a SUSTAINED exit retargets.
                    // Jitter across the sticky boundary flapped the outline
                    // and ring tint every frame; the old target now lingers
                    // hoverGraceMS, and popping back inside cancels the exit.
                    if hoverExitSince == nil { hoverExitSince = now }
                    if now - hoverExitSince! >= config.hoverGraceMS / 1000 {
                        hoveredTarget = latestHover
                        hoverExitSince = nil
                    }
                } else {
                    hoverExitSince = nil
                    if let fresh = latestHover, fresh.windowID == hov.windowID {
                        hoveredTarget = fresh // same window — refresh its frame
                    }
                }
            } else {
                hoveredTarget = latestHover // acquiring is instant; only letting go is damped
                hoverExitSince = nil
            }
        } else if !handFresh {
            hoveredTarget = nil
            latestHover = nil
        }

        // Grab once the pinch has ARMED (held grabArmMS), not on its raw edge
        // — the arm outlives every transitional pose, and it buys the async
        // hover query time to land, so pinching right as the pointer arrives
        // on a window commits instead of silently missing. Past the acquire
        // cap with still nothing hovered, the pinch is spent — like pressing
        // a mouse button over the desktop. Drag from the eased knuckle anchor.
        if state.pinching, !grabSpent, grabbedTarget == nil, handFresh,
           now - pinchBegan >= config.grabArmMS / 1000 {
            if let t = hoveredTarget, let a = anchor {
                grabSpent = true
                grabbedTarget = t
                let aCG = cgPoint(fromView: a)
                grabOffsetCG = CGPoint(x: t.frame.origin.x - aCG.x, y: t.frame.origin.y - aCG.y)
                lastDragOrigin = t.frame.origin
                mover.beginDrag(t, raise: config.raiseOnGrab)
            } else if now - pinchBegan >= grabAcquireCap {
                grabSpent = true
            }
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

    /// Scroll grab → wheel pixels. An eased shadow of the pointer target
    /// supplies smooth per-frame deltas (the visible ring is frozen); on
    /// release the tracked velocity decays out as a trackpad-style coast.
    /// Natural direction = content follows the hand.
    private func stepScroll(config: Config, dt: CFTimeInterval, k: CGFloat, active: Bool) {
        // Derived from the config both call sites already pass — a parameter
        // could silently desync from the mode it must mirror.
        let sandbox = config.useMockWindows || config.tourSandbox
        if sandbox != lastScrollSandbox {
            lastScrollSandbox = sandbox
            // Momentum must not cross worlds: velocity built coasting the
            // practice pane would otherwise land on real content (and vice
            // versa) the frame the sandbox toggles.
            scrollVel = .zero
            scrollEased = nil
        }
        if active {
            let t = scrollNormTarget
            var e = scrollEased ?? t
            let old = e
            e.x += (t.x - e.x) * k
            e.y += (t.y - e.y) * k
            scrollEased = e
            let sign: CGFloat = config.scrollNatural ? -1 : 1
            let g = CGFloat(config.scrollGain) * sign
            let dx = (e.x - old.x) * bounds.width * g
            let dy = (e.y - old.y) * bounds.height * g
            if sandbox {
                mockWindows.first(where: { $0.scrollable })?.scrollContent(byWheel: dy)
            } else {
                mouse.scroll(dx: dx, dy: dy)
            }
            let f = CGFloat(1.0 / (dt * 60)) // velocity per 60fps frame
            scrollVel.dx = scrollVel.dx * 0.7 + dx * f * 0.3
            scrollVel.dy = scrollVel.dy * 0.7 + dy * f * 0.3
        } else {
            scrollEased = nil
            guard config.scrollMomentum, abs(scrollVel.dx) + abs(scrollVel.dy) > 0.4 else {
                scrollVel = .zero
                return
            }
            let frames = CGFloat(dt * 60)
            if sandbox {
                mockWindows.first(where: { $0.scrollable })?
                    .scrollContent(byWheel: scrollVel.dy * frames)
            } else {
                mouse.scroll(dx: scrollVel.dx * frames, dy: scrollVel.dy * frames)
            }
            let decay = pow(0.93, frames)
            scrollVel.dx *= decay
            scrollVel.dy *= decay
        }
    }

    // MARK: - Dictation

    private func beginDictation() {
        mouse.completeClickEarly() // click lands: field focused, caret placed
        dictating = true
        dictationDisplay = "🎤 listening…"
        speech.onPartial = { [weak self] text in
            guard let self, self.dictating, !text.isEmpty else { return }
            self.dictationDisplay = "🎤 " + text
        }
        speech.start { [weak self] ok in
            guard let self, !ok else { return }
            let reason = self.speech.unavailableReason
            self.dictationDisplay = reason.isEmpty
                ? "🎤 allow Microphone + Speech, then try again" : "🎤 \(reason)"
            self.dictating = false
            self.clearDictationDisplaySoon()
        }
    }

    /// Pinch released: stop the mic, type the final transcript into the field.
    private func endDictation() {
        dictating = false
        dictationDisplay = "🎤 …"
        speech.stop { [weak self] text in
            guard let self else { return }
            if !text.isEmpty { self.mouse.typeText(text) }
            self.dictationDisplay = nil
        }
    }

    private func abortDictation() {
        dictating = false
        dictationDisplay = nil
        speech.cancel()
    }

    private func clearDictationDisplaySoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !self.dictating else { return }
            self.dictationDisplay = nil
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
        // One meter above the cursor: green = swipe/thumb toward a Space
        // switch, red = ✌ held toward turning the app off, indigo = 🤙 held
        // toward toggling mouse mode.
        let peace = state.peaceProgress
        let shaka = state.shakaProgress
        let send = state.sendProgress
        let progress = peace > 0.02 ? peace : shaka > 0.02 ? shaka
            : send > 0.02 ? send : abs(state.swipeProgress)
        if let p = pointer, handFresh, progress > 0.02 {
            swipeBarBack.position = CGPoint(x: p.x, y: p.y + ringRadius + 18)
            swipeBarBack.opacity = 1
            swipeBarFill.backgroundColor = (peace > 0.02 ? NSColor.systemRed
                : shaka > 0.02 ? NSColor.systemIndigo
                : send > 0.02 ? NSColor.systemMint : NSColor.systemGreen).cgColor
            swipeBarFill.bounds = CGRect(x: 0, y: 0, width: CGFloat(progress) * 64, height: 6)
            swipeBarFill.position = CGPoint(x: 32, y: 3)
        } else {
            swipeBarBack.opacity = 0
        }

        // --- Swipe flash fade. Skip the no-op write once faded: CALayer
        // setters don't compare, so re-assigning 0 forever kept dirtying it.
        let flashOpacity = Float(max(0, 1 - (now - swipeFlashTime) / 0.8))
        if swipeFlash.opacity != flashOpacity { swipeFlash.opacity = flashOpacity }

        // --- Status line.
        let text: String
        if let prompt {
            text = prompt
        } else if let dictation = dictationDisplay {
            text = dictation
        } else if state.fps > 0 {
            let gesture = state.peaceProgress > 0.02 ? "✌ hold to turn off…"
                : state.shakaProgress > 0.02 ? "🤙 hold to toggle mouse…"
                : state.sendProgress > 0.02 ? "👍 hold to send ⏎…"
                : state.pinching ? "PINCH"
                : state.scrollGrab ? "FIST scroll"
                : state.thumbDir != 0 ? (state.thumbDir > 0 ? "THUMB ⟶ hold…" : "⟵ THUMB hold…")
                : state.swiping ? (state.swipeArmed ? "PALM ✓ armed" : "PALM open")
                : "point"
            let mode = configProvider().mouseMode ? " · MOUSE" : ""
            text = String(format: "AirControl M3%@ · %.0f fps · %@%@",
                          mode, state.fps, gesture, handFresh ? "" : " · no hand")
        } else {
            text = "AirControl M3 · show your hand to the camera"
        }
        // CATextLayer re-rasterizes its text on every string assignment, even
        // an identical one — at render rate that was a bitmap redraw per
        // frame. Only touch it when the words actually change.
        if text != lastStatusText {
            lastStatusText = text
            statusLabel.string = text
        }
    }
}
