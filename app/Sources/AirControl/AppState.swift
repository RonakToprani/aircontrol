import AppKit
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var enabled = false {
        didSet {
            guard enabled != oldValue else { return }
            enabled ? start() : stop()
        }
    }
    @Published var showPreview = false {
        didSet { updatePreview() }
    }
    @Published var showTuning = false {
        didSet { updateTuning() }
    }
    @Published private(set) var stats = GestureState()
    @Published private(set) var handVisible = false
    @Published private(set) var cameraError: String?
    @Published private(set) var accessibilityOK = true
    @Published private(set) var axLatencyMS: Double = 0

    var needsAccessibility: Bool {
        enabled && configStore.config.switchSpaces && !accessibilityOK
    }

    let configStore = ConfigStore()

    private let tracker = HandTracker()
    private let engine = GestureEngine()
    private let mover = WindowMover()
    private var overlay: OverlayController?
    private var preview: PreviewController?
    private var tuning: TuningPanelController?
    private var lastUIUpdate: CFTimeInterval = 0
    private var lastAXCheck: CFTimeInterval = 0

    // Pinch-corner calibration flow (PLAN §5.4).
    private enum CalStage { case idle, waitTopLeft, waitBottomRight }
    private var calStage: CalStage = .idle
    private var calPinchStart: CFTimeInterval?
    private var calNeedRelease = false
    private var calTopLeft: CGPoint?
    private var calPrevShowPreview = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Keep the tracker's 1€ filters in sync with the tuning sliders.
        configStore.$config
            .removeDuplicates { $0.oneEuroMinCutoff == $1.oneEuroMinCutoff
                && $0.oneEuroBeta == $1.oneEuroBeta
                && $0.jumpRejectDist == $1.jumpRejectDist
                && $0.axWriteMinIntervalMS == $1.axWriteMinIntervalMS }
            .sink { [weak self] c in
                self?.tracker.setFilterParams(minCutoff: c.oneEuroMinCutoff, beta: c.oneEuroBeta)
                self?.tracker.setJumpReject(c.jumpRejectDist)
                self?.mover.setMinWriteInterval(ms: c.axWriteMinIntervalMS)
            }
            .store(in: &cancellables)
        mover.onLatency = { [weak self] ms in self?.axLatencyMS = ms }

        // The engine's pointer-freeze is keyed to macOS actually switching
        // Spaces — never to the swipe gesture, which may switch nothing.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { // observer queue is .main
                guard let self, self.enabled else { return }
                self.engine.beginSettle(duration: self.configStore.config.postSwipeSettleMS / 1000)
            }
        }
    }

    var statusLine: String {
        if let error = cameraError { return "⚠︎ \(error)" }
        if !enabled { return "Off" }
        if !handVisible { return "On — no hand detected" }
        return String(format: "Tracking · %.0f detections/sec", stats.fps)
    }

    private func start() {
        cameraError = nil
        if configStore.config.switchSpaces {
            accessibilityOK = SpaceSwitcher.requestTrust()
        }
        let overlay = OverlayController(screen: NSScreen.main ?? NSScreen.screens[0],
                                        configProvider: { [configStore] in configStore.config },
                                        mover: mover)
        self.overlay = overlay
        overlay.show()

        tracker.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                let state = self.engine.process(frame, config: self.configStore.config,
                                                now: CACurrentMediaTime())
                if self.calStage != .idle {
                    self.stepCalibration(frame: frame, state: state, now: CACurrentMediaTime())
                    // While calibrating, the pinches are corner markers — no
                    // grabbing, no swiping, no Space switching.
                    var neutered = state
                    neutered.pinching = false
                    neutered.swipeEvent = nil
                    neutered.swipeProgress = 0
                    neutered.thumbDir = 0
                    self.overlay?.update(state: neutered)
                } else {
                    self.overlay?.update(state: state)
                }
                self.preview?.update(joints: frame?.joints)

                if state.peaceEvent, self.calStage == .idle {
                    self.enabled = false // ✌ — camera off, icon goes hollow
                    return
                }
                if let event = state.swipeEvent, self.calStage == .idle,
                   self.configStore.config.switchSpaces {
                    self.accessibilityOK = SpaceSwitcher.isTrusted
                    let dir = self.configStore.config.swipeNatural ? -event : event
                    SpaceSwitcher.post(direction: dir, warpTo: self.overlay?.pointerCG())
                }

                // Menu/panel-facing published state, throttled to ~10 Hz —
                // except gesture edges, which publish immediately.
                let now = CACurrentMediaTime()
                if now - self.lastAXCheck > 1.0 {
                    self.lastAXCheck = now
                    let trusted = SpaceSwitcher.isTrusted
                    if trusted != self.accessibilityOK { self.accessibilityOK = trusted }
                }
                if now - self.lastUIUpdate > 0.1
                    || state.pinching != self.stats.pinching
                    || state.swipeEvent != nil {
                    self.lastUIUpdate = now
                    self.stats = state
                    self.handVisible = state.handVisible
                }
            }
        }
        tracker.start { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.cameraError = error
                if error != nil {
                    self.enabled = false
                } else {
                    self.updatePreview()
                    self.updateTuning()
                }
            }
        }
    }

    func startCalibration() {
        guard enabled else { return }
        calStage = .waitTopLeft
        calTopLeft = nil
        calPinchStart = nil
        calNeedRelease = false
        // Pop the hand preview so you can watch yourself draw the box;
        // restored to its previous state when the flow ends.
        calPrevShowPreview = showPreview
        if !showPreview { showPreview = true }
        overlay?.setPrompt("Calibrating — watch the hand preview panel")
    }

    func resetCalibration() {
        configStore.config.calibration = nil
        endCalibration(message: nil)
    }

    private func endCalibration(message: String?) {
        calStage = .idle
        preview?.setCalibration(nil)
        overlay?.setPrompt(message)
        let closePreview = !calPrevShowPreview
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.calStage == .idle else { return }
            self.overlay?.setPrompt(nil)
            if closePreview, self.showPreview { self.showPreview = false }
        }
    }

    /// Two pinch-holds define the comfortable hand rect: top-left, then
    /// bottom-right. Captured from RAW camera-space fingertips, so re-running
    /// is always independent of the current mapping. Progress is drawn live
    /// on the hand preview (hold ring, captured corner, rubber-band rect).
    private func stepCalibration(frame: LandmarkFrame?, state: GestureState, now: CFTimeInterval) {
        var holdProgress = 0.0
        defer {
            if calStage != .idle {
                let text: String
                if frame == nil {
                    text = "Show your hand to the camera"
                } else if calNeedRelease {
                    text = "Release the pinch…"
                } else if calStage == .waitTopLeft {
                    text = "1/2 · pinch-hold at your comfortable TOP-LEFT"
                } else {
                    text = "2/2 · pinch-hold at your comfortable BOTTOM-RIGHT"
                }
                preview?.setCalibration(CalibrationViz(
                    instruction: text,
                    holdProgress: holdProgress,
                    capturedTopLeft: calTopLeft,
                    currentTip: frame?.indexTip,
                    stage2: calStage == .waitBottomRight))
            }
        }
        guard let f = frame else {
            calPinchStart = nil
            return
        }
        guard state.pinching else {
            calPinchStart = nil
            calNeedRelease = false
            return
        }
        guard !calNeedRelease else { return }
        if calPinchStart == nil { calPinchStart = now }
        holdProgress = min((now - calPinchStart!) / 0.6, 1)
        guard holdProgress >= 1 else { return }
        calPinchStart = nil
        calNeedRelease = true

        if calStage == .waitTopLeft {
            calTopLeft = f.indexTip
            calStage = .waitBottomRight
            return
        }
        let tl = calTopLeft ?? .zero
        let br = f.indexTip
        let rect = CalRect(minX: Double(min(tl.x, br.x)), minY: Double(min(tl.y, br.y)),
                           maxX: Double(max(tl.x, br.x)), maxY: Double(max(tl.y, br.y)))
        if rect.maxX - rect.minX < 0.15 || rect.maxY - rect.minY < 0.15 {
            calStage = .waitTopLeft
            calTopLeft = nil
            return
        }
        configStore.config.calibration = rect
        endCalibration(message: "Calibrated ✓ — your comfort box now spans the whole desktop")
    }

    private func stop() {
        calStage = .idle
        tracker.stop()
        tracker.onFrame = nil
        overlay?.close()
        overlay = nil
        handVisible = false
        stats = GestureState()
        updatePreview()
        updateTuning()
    }

    /// The preview panel exists only while enabled AND requested — the camera
    /// session it displays isn't running otherwise.
    private func updatePreview() {
        if enabled, showPreview, preview == nil {
            let p = PreviewController(session: tracker.session)
            p.onClose = { [weak self] in
                guard let self else { return }
                self.preview = nil
                self.showPreview = false
            }
            preview = p
            p.show()
        } else if !enabled || !showPreview, let p = preview {
            preview = nil
            p.close()
        }
    }

    private func updateTuning() {
        if enabled, showTuning, tuning == nil {
            let t = TuningPanelController(store: configStore, app: self)
            t.onClose = { [weak self] in
                guard let self else { return }
                self.tuning = nil
                self.showTuning = false
            }
            tuning = t
            t.show()
        } else if !enabled || !showTuning, let t = tuning {
            tuning = nil
            t.close()
        }
    }
}
