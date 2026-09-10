import AVFoundation
import Vision
import QuartzCore

/// Camera capture + Vision hand-pose detection. Everything runs on a private
/// serial queue; results are delivered via `onFrame` (also on that queue —
/// callers hop to main themselves). `onFrame` receives nil when no hand is
/// confidently visible in a processed frame.
final class HandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((LandmarkFrame?) -> Void)?
    /// Fired on the main thread when another app grabs the camera (true) and
    /// when it hands it back (false) — the menu-bar status reflects it.
    var onInterruption: ((Bool) -> Void)?

    /// Exposed for the hand-preview window's AVCaptureVideoPreviewLayer.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "aircontrol.camera", qos: .userInteractive)
    private let request = VNDetectHumanHandPoseRequest()
    private var configured = false
    /// Whether capture is *supposed* to be running (set by start/stop, on the
    /// camera queue) — the runtime-error restart must never outlive a stop().
    private var wantsRunning = false

    // Idle rest: while resting we still receive every camera frame but run
    // Vision on only every Nth, cutting the app's biggest energy cost when no
    // one's using it. 1 = full rate. Any detected hand snaps it back to 1.
    private var frameCounter: UInt64 = 0
    private var idleSkip = 1
    // Lightweight mode reuses the same skip pattern at every 2nd frame — a
    // 30fps camera lands at ~15 Hz detection, plenty for hand landmarks. The
    // deeper idle skip still wins while resting (max of the two).
    private var lightweight = false
    private let lightweightSkip = 2

    private var lastDetectionTime: CFTimeInterval = 0
    private var fpsEMA: Double = 0

    private let minJointConfidence: Float = 0.3

    // 1€ filters for the control points; reset after a tracking gap so a
    // reacquired hand doesn't get smoothed against stale history.
    private let indexTipFilter = PointFilter()
    private let indexMCPFilter = PointFilter()
    private let thumbTipFilter = PointFilter()
    private let wristFilter = PointFilter()
    private let trackingGapReset: CFTimeInterval = 0.3
    private var lastAcceptedWrist: CGPoint?
    private var pendingJump: CGPoint?
    private var jumpRejectDist: Double = 0.25

    override init() {
        super.init()
        request.maximumHandCount = 1

        // Camera contention: another app can seize the camera out from under
        // us. Surface it as status and resume cleanly when it's returned;
        // never a dialog. Runtime errors get one restart attempt.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(sessionInterrupted),
                       name: .AVCaptureSessionWasInterrupted, object: session)
        nc.addObserver(self, selector: #selector(sessionInterruptionEnded),
                       name: .AVCaptureSessionInterruptionEnded, object: session)
        nc.addObserver(self, selector: #selector(sessionRuntimeError),
                       name: .AVCaptureSessionRuntimeError, object: session)
    }

    @objc private func sessionInterrupted() {
        DispatchQueue.main.async { self.onInterruption?(true) }
    }

    @objc private func sessionInterruptionEnded() {
        DispatchQueue.main.async { self.onInterruption?(false) }
    }

    @objc private func sessionRuntimeError() {
        // A transient capture error — give the session one gentle restart.
        queue.asyncAfter(deadline: .now() + 0.5) {
            // wantsRunning: if the user disabled (or the Mac slept) since the
            // error, restarting would relight the camera while the menu says
            // Off — the one thing this app must never do.
            guard self.configured, self.wantsRunning, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    /// Rest mode: run Vision on every 4th frame instead of every one. Called
    /// from AppState when no hand has been seen for the idle timeout.
    func setIdle(_ idle: Bool) {
        queue.async { self.idleSkip = idle ? 4 : 1 }
    }

    /// Lightweight mode: 640×480 capture + half-rate detection. Vision's hand
    /// network downsamples its input anyway, so the 720p decode/scale it
    /// replaces was pure cost — the two together are the bulk of the app's
    /// CPU on older Macs. Live-switchable; the session reconfigures in place.
    func setLightweight(_ on: Bool) {
        queue.async {
            guard on != self.lightweight else { return }
            self.lightweight = on
            if self.configured {
                self.session.beginConfiguration()
                self.applyPreset()
                self.session.commitConfiguration()
            }
        }
    }

    /// Starts capture, requesting camera permission if needed.
    /// `onStatus` is called with nil on success or a user-facing error string.
    func start(onStatus: @escaping (String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configureAndRun(onStatus: onStatus) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                self.queue.async {
                    if granted {
                        self.configureAndRun(onStatus: onStatus)
                    } else {
                        onStatus("Camera permission denied")
                    }
                }
            }
        default:
            onStatus("Camera access is off — enable it in System Settings › Privacy & Security › Camera")
        }
    }

    func stop() {
        queue.async {
            self.wantsRunning = false
            self.session.stopRunning()
            self.lastDetectionTime = 0
            self.fpsEMA = 0
            self.resetFilters()
        }
    }

    private func configureAndRun(onStatus: @escaping (String?) -> Void) {
        if !configured {
            session.beginConfiguration()
            applyPreset()

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                session.commitConfiguration()
                onStatus("No usable camera found")
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                onStatus("Could not attach camera output")
                return
            }
            session.addOutput(output)
            session.commitConfiguration()
            configured = true
        }
        wantsRunning = true
        session.startRunning()
        onStatus(nil)
    }

    /// Must run between beginConfiguration/commitConfiguration on the camera
    /// queue. Landmarks don't need 1080p — 640×480 keeps them accurate while
    /// slashing capture + Vision-preprocessing cost on older hardware.
    private func applyPreset() {
        if lightweight, session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else {
            session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Rest mode / lightweight: skip the Vision pass on most frames. Cheap
        // and correct — hold gestures time by wall clock, and the moment a
        // processed frame finds a hand, AppState restores rest to full rate.
        frameCounter &+= 1
        let skip = max(idleSkip, lightweight ? lightweightSkip : 1)
        if skip > 1, frameCounter % UInt64(skip) != 0 { return }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            onFrame?(nil)
            return
        }

        guard let observation = request.results?.first,
              let indexTip = point(.indexTip, in: observation),
              let indexMCP = point(.indexMCP, in: observation),
              let thumbTip = point(.thumbTip, in: observation),
              let wrist = point(.wrist, in: observation)
        else {
            onFrame?(nil)
            return
        }

        let now = CACurrentMediaTime()
        if lastDetectionTime > 0, now - lastDetectionTime > trackingGapReset {
            resetFilters()
            lastAcceptedWrist = nil
        }

        // Single-frame teleport rejection: a confident-but-wrong detection can
        // fling the pointer across the screen for one frame (the 1€ filter
        // passes fast motion through by design). An impossible jump must
        // persist for two consecutive frames before it's believed.
        if let last = lastAcceptedWrist {
            let jump = hypot(wrist.x - last.x, wrist.y - last.y)
            if Double(jump) > jumpRejectDist {
                if let pending = pendingJump,
                   Double(hypot(wrist.x - pending.x, wrist.y - pending.y)) <= jumpRejectDist {
                    resetFilters() // confirmed relocation — don't smear across it
                    pendingJump = nil
                } else {
                    pendingJump = wrist
                    onFrame?(nil)
                    return
                }
            } else {
                pendingJump = nil
            }
        }
        lastAcceptedWrist = wrist
        if lastDetectionTime > 0 {
            let inst = 1.0 / max(now - lastDetectionTime, 0.001)
            fpsEMA = fpsEMA == 0 ? inst : fpsEMA * 0.9 + inst * 0.1
        }
        lastDetectionTime = now

        var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
        if let all = try? observation.recognizedPoints(.all) {
            for (name, p) in all where p.confidence >= minJointConfidence {
                joints[name] = CGPoint(x: 1.0 - p.location.x, y: p.location.y)
            }
        }

        onFrame?(LandmarkFrame(
            indexTip: indexTipFilter.filter(indexTip, at: now),
            indexMCP: indexMCPFilter.filter(indexMCP, at: now),
            thumbTip: thumbTipFilter.filter(thumbTip, at: now),
            wrist: wristFilter.filter(wrist, at: now),
            joints: joints,
            fps: fpsEMA,
            timestamp: now
        ))
    }

    private func resetFilters() {
        indexTipFilter.reset()
        indexMCPFilter.reset()
        thumbTipFilter.reset()
        wristFilter.reset()
    }

    /// Live-tunable 1€ parameters (called from the tuning panel).
    func setFilterParams(minCutoff: Double, beta: Double) {
        queue.async {
            for f in [self.indexTipFilter, self.indexMCPFilter, self.thumbTipFilter, self.wristFilter] {
                f.setParams(minCutoff: minCutoff, beta: beta)
            }
        }
    }

    func setJumpReject(_ dist: Double) {
        queue.async { self.jumpRejectDist = dist }
    }

    /// Vision → canonical coords: Vision is normalized with origin bottom-left
    /// and the buffer is NOT mirrored, so flip x to get mirror-mode behavior
    /// (hand moves right → pointer moves right).
    private func point(_ joint: VNHumanHandPoseObservation.JointName,
                       in observation: VNHumanHandPoseObservation) -> CGPoint? {
        guard let p = try? observation.recognizedPoint(joint), p.confidence >= minJointConfidence else {
            return nil
        }
        return CGPoint(x: 1.0 - p.location.x, y: p.location.y)
    }
}
