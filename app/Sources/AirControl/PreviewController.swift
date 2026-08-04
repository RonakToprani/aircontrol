import AppKit
import AVFoundation
import Vision

/// Live state of the pinch-corner calibration flow, drawn on the preview so
/// you can watch yourself define the comfort box.
struct CalibrationViz {
    var instruction: String
    var holdProgress: Double      // 0…1 while a pinch is being held
    var capturedTopLeft: CGPoint? // normalized camera coords
    var currentTip: CGPoint?      // normalized camera coords
    var stage2: Bool              // drawing the rect toward bottom-right
}

/// A small floating "hand preview" panel: the mirrored camera feed with the
/// detected hand skeleton drawn on top — so you can see at a glance whether
/// your hand is in frame and being read correctly. Development/diagnostic aid.
final class PreviewController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()
    private let calLayer = CAShapeLayer()
    private let holdRing = CAShapeLayer()
    private let instruction = CATextLayer()

    private static let chains: [[VNHumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]

    init(session: AVCaptureSession) {
        // 16:9 to match the 720p capture, so normalized coords line up 1:1.
        let size = NSSize(width: 356, height: 200)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 16,
                             y: screen.visibleFrame.minY + 16)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.title = "Hand preview"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        if let connection = previewLayer.connection {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        super.init()

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        previewLayer.frame = content.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        skeleton.frame = content.bounds
        skeleton.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        skeleton.strokeColor = NSColor.systemTeal.cgColor
        skeleton.fillColor = NSColor.white.cgColor
        skeleton.lineWidth = 2
        skeleton.lineCap = .round
        skeleton.lineJoin = .round

        calLayer.frame = content.bounds
        calLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        calLayer.strokeColor = NSColor.systemYellow.cgColor
        calLayer.fillColor = NSColor.clear.cgColor
        calLayer.lineWidth = 2
        calLayer.lineDashPattern = [6, 4]

        holdRing.frame = content.bounds
        holdRing.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        holdRing.strokeColor = NSColor.systemGreen.cgColor
        holdRing.fillColor = NSColor.clear.cgColor
        holdRing.lineWidth = 4
        holdRing.lineCap = .round

        instruction.fontSize = 12
        instruction.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        instruction.foregroundColor = NSColor.white.cgColor
        instruction.backgroundColor = NSColor.black.withAlphaComponent(0.65).cgColor
        instruction.alignmentMode = .center
        instruction.contentsScale = 2
        instruction.frame = CGRect(x: 0, y: size.height - 24, width: size.width, height: 24)
        instruction.autoresizingMask = [.layerWidthSizable, .layerMinYMargin]
        instruction.isHidden = true

        content.layer?.addSublayer(previewLayer)
        content.layer?.addSublayer(skeleton)
        content.layer?.addSublayer(calLayer)
        content.layer?.addSublayer(holdRing)
        content.layer?.addSublayer(instruction)
        panel.contentView = content
        panel.delegate = self
    }

    /// Draw (or clear, with nil) the calibration walkthrough on the preview.
    func setCalibration(_ viz: CalibrationViz?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let viz else {
            instruction.isHidden = true
            calLayer.path = nil
            holdRing.path = nil
            return
        }
        instruction.isHidden = false
        instruction.string = viz.instruction
        let w = skeleton.bounds.width
        let h = skeleton.bounds.height
        let path = CGMutablePath()
        if let tl = viz.capturedTopLeft {
            let p = CGPoint(x: tl.x * w, y: tl.y * h)
            path.move(to: CGPoint(x: p.x - 9, y: p.y))
            path.addLine(to: CGPoint(x: p.x + 9, y: p.y))
            path.move(to: CGPoint(x: p.x, y: p.y - 9))
            path.addLine(to: CGPoint(x: p.x, y: p.y + 9))
            if viz.stage2, let tip = viz.currentTip {
                let q = CGPoint(x: tip.x * w, y: tip.y * h)
                path.addRect(CGRect(x: min(p.x, q.x), y: min(p.y, q.y),
                                    width: abs(q.x - p.x), height: abs(q.y - p.y)))
            }
        }
        calLayer.path = path
        if viz.holdProgress > 0, let tip = viz.currentTip {
            let q = CGPoint(x: tip.x * w, y: tip.y * h)
            holdRing.path = CGPath(ellipseIn: CGRect(x: q.x - 14, y: q.y - 14, width: 28, height: 28),
                                   transform: nil)
            holdRing.strokeEnd = CGFloat(viz.holdProgress)
        } else {
            holdRing.path = nil
        }
    }

    func show() { panel.orderFrontRegardless() }

    func close() {
        panel.delegate = nil
        panel.close()
    }

    /// Canonical coords (normalized, mirrored, origin bottom-left) map straight
    /// onto the mirrored preview layer.
    func update(joints: [VNHumanHandPoseObservation.JointName: CGPoint]?) {
        let path = CGMutablePath()
        if let joints {
            let w = skeleton.bounds.width
            let h = skeleton.bounds.height
            func at(_ name: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                joints[name].map { CGPoint(x: $0.x * w, y: $0.y * h) }
            }
            for chain in Self.chains {
                var started = false
                for name in chain {
                    guard let p = at(name) else { started = false; continue }
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
            }
            for name in joints.keys {
                if let p = at(name) {
                    path.addEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
                }
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        skeleton.path = path
        CATransaction.commit()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
