import AppKit
import AVFoundation
import Vision

/// A small floating "hand preview" panel: the mirrored camera feed with the
/// detected hand skeleton drawn on top — so you can see at a glance whether
/// your hand is in frame and being read correctly. Development/diagnostic aid.
final class PreviewController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let panel: NSPanel
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let skeleton = CAShapeLayer()

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

        content.layer?.addSublayer(previewLayer)
        content.layer?.addSublayer(skeleton)
        panel.contentView = content
        panel.delegate = self
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
