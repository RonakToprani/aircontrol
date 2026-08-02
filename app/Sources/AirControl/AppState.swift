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
                self.overlay?.update(state: state)
                self.preview?.update(joints: frame?.joints)

                if let event = state.swipeEvent, self.configStore.config.switchSpaces {
                    self.accessibilityOK = SpaceSwitcher.isTrusted
                    let dir = self.configStore.config.swipeNatural ? -event : event
                    SpaceSwitcher.post(direction: dir)
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

    private func stop() {
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
