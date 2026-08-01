import AVFoundation
import Vision
import QuartzCore

/// Camera capture + Vision hand-pose detection. Everything runs on a private
/// serial queue; results are delivered via `onFrame` (also on that queue —
/// callers hop to main themselves). `onFrame` receives nil when no hand is
/// confidently visible in a processed frame.
final class HandTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onFrame: ((LandmarkFrame?) -> Void)?

    /// Exposed for the hand-preview window's AVCaptureVideoPreviewLayer.
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "aircontrol.camera", qos: .userInteractive)
    private let request = VNDetectHumanHandPoseRequest()
    private var configured = false

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

    override init() {
        super.init()
        request.maximumHandCount = 1
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
            self.session.stopRunning()
            self.lastDetectionTime = 0
            self.fpsEMA = 0
            self.resetFilters()
        }
    }

    private func configureAndRun(onStatus: @escaping (String?) -> Void) {
        if !configured {
            session.beginConfiguration()
            session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high

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
        session.startRunning()
        onStatus(nil)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
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
        }
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
