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
    @Published private(set) var detectFPS: Double = 0
    @Published private(set) var handVisible = false
    @Published private(set) var cameraError: String?

    private let tracker = HandTracker()
    private var overlay: OverlayController?
    private var preview: PreviewController?
    private var lastUIUpdate: CFTimeInterval = 0

    var statusLine: String {
        if let error = cameraError { return "⚠︎ \(error)" }
        if !enabled { return "Off" }
        if !handVisible { return "On — no hand detected" }
        return String(format: "Tracking · %.0f detections/sec", detectFPS)
    }

    private func start() {
        cameraError = nil
        let overlay = OverlayController(screen: NSScreen.main ?? NSScreen.screens[0])
        self.overlay = overlay
        overlay.show()

        tracker.onFrame = { [weak self] frame in
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                self.overlay?.update(frame: frame)
                self.preview?.update(joints: frame?.joints)
                // Throttle menu-facing published state to ~4 Hz.
                let now = CACurrentMediaTime()
                if now - self.lastUIUpdate > 0.25 {
                    self.lastUIUpdate = now
                    self.handVisible = frame != nil
                    if let f = frame { self.detectFPS = f.fps }
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
        detectFPS = 0
        updatePreview()
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
}
