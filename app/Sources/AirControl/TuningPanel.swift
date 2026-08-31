import AppKit
import SwiftUI

/// Floating tuning panel: every Config field as a live slider plus the live
/// readouts that explain *why* a gesture isn't triggering — the Phase 1
/// tuning workflow, in-app.
final class TuningPanelController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let panel: NSPanel

    @MainActor
    init(store: ConfigStore, app: AppState) {
        let size = NSSize(width: 340, height: 620)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let origin = NSPoint(x: screen.visibleFrame.maxX - size.width - 16,
                             y: screen.visibleFrame.maxY - size.height - 16)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.title = "AirControl tuning"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TuningView(store: store, app: app))
        super.init()
        panel.delegate = self
    }

    func show() { panel.orderFrontRegardless() }

    func close() {
        panel.delegate = nil
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

struct TuningView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var app: AppState

    var body: some View {
        Form {
            Section("Pointer") {
                Toggle("Cursor at knuckle (index MCP)", isOn: $store.config.pointerAtKnuckle)
                    .font(.caption)
                slider("Position smoothing (posAlpha)", $store.config.posAlpha, 0.1...0.8, "%.2f")
                slider("1€ steadiness floor (minCutoff)", $store.config.oneEuroMinCutoff, 0.2...3.0, "%.2f",
                       help: "Lower = steadier when still, but lazier")
                slider("1€ speed response (beta)", $store.config.oneEuroBeta, 0...10, "%.1f",
                       help: "Higher = less lag on fast moves")
                slider("Edge margin", $store.config.margin, 0.05...0.3, "%.2f",
                       help: store.config.calibration == nil
                           ? "Active (no calibration yet — run it from the menu bar)"
                           : "Inactive — calibrated hand rect is in use")
                readout("Calibration", store.config.calibration != nil ? "custom rect ✓" : "margin default")
                slider("Teleport reject distance", $store.config.jumpRejectDist, 0.1...0.6, "%.2f",
                       help: "1-frame jumps beyond this are treated as misdetections; lower = stricter")
                slider("Precision while dragging", $store.config.precisionOnPinch, 0.3...1.0, "%.2f",
                       help: "Hand motion scaled down during a drag for steadier placement; 1 = off")
            }
            Section("Pinch") {
                slider("Signal smoothing (pinchAlpha)", $store.config.pinchAlpha, 0.1...0.9, "%.2f")
                slider("Threshold", $store.config.pinchThresh, 0.2...0.8, "%.2f")
                slider("Release hysteresis", $store.config.pinchHyst, 0.02...0.3, "%.2f")
            }
            Section("Mouse mode") {
                Toggle("Pointer drives the real cursor", isOn: $store.config.mouseMode)
                    .font(.caption)
                Text("Pinch = left click · pinch-hold = drag · two quick pinches = double-click. Window grabbing pauses while on (pinch-drag a title bar instead). Needs Accessibility.")
                    .font(.caption2).foregroundStyle(.tertiary)
                slider("Click vs drag slop (px)", $store.config.mouseDragSlopPx, 4...40, "%.0f",
                       help: "Cursor pins at pinch-down until the hand moves this far — jitter stays a clean click")
                slider("Click commit delay (ms)", $store.config.mouseDownDelayMS, 0...300, "%.0f",
                       help: "Mouse-down waits this long so a closing fist (which passes through the pinch shape) can't misfire a click")
                Toggle("Hide the system cursor (the ring is the cursor)", isOn: $store.config.hideSystemCursor)
                    .font(.caption)
                Toggle("🤙 shaka toggles mouse mode", isOn: $store.config.shakaToggle)
                    .font(.caption)
                slider("Shaka hold time (ms)", $store.config.shakaHoldMS, 300...1500, "%.0f",
                       help: "Thumb + little finger out, middle three folded; hold until the indigo meter fills")
                slider("Scroll gain", $store.config.scrollGain, 0.5...6.0, "%.1f",
                       help: "Make a fist (thumb tucked in) to grab the page; hand motion scrolls it")
                slider("Fist arm time (ms)", $store.config.scrollArmMS, 0...400, "%.0f",
                       help: "Fist must hold this long before scrolling starts — rides out a pinch forming")
                Toggle("Natural scroll (content follows hand)", isOn: $store.config.scrollNatural)
                    .font(.caption)
                Toggle("Scroll momentum (coasts after release)", isOn: $store.config.scrollMomentum)
                    .font(.caption)
                Toggle("Pinch opens files (Finder gets a double-click)", isOn: $store.config.pinchOpensFiles)
                    .font(.caption)
            }
            Section("4-finger swipe") {
                slider("Travel distance", $store.config.swipeDist, 0.05...0.4, "%.2f")
                slider("Time window (ms)", $store.config.swipeMaxTimeMS, 250...1000, "%.0f")
                slider("Cooldown (ms)", $store.config.swipeCooldownMS, 200...2000, "%.0f")
                Stepper("Min fingers: \(store.config.swipeMinFingers)",
                        value: $store.config.swipeMinFingers, in: 3...4)
                slider("Finger extended threshold", $store.config.extendThresh, 1.0...1.6, "%.2f")
                slider("Straightness", $store.config.swipeStraightness, 0.3...1.0, "%.2f",
                       help: "Higher = one clean stroke required; waves that double back are rejected")
                slider("Max vertical drift", $store.config.swipeMaxVertRatio, 0.2...2.0, "%.2f",
                       help: "Lower = stroke must be level; arcs and diagonal moves are rejected")
                slider("Arm: hold-still time (ms)", $store.config.swipeArmMS, 50...500, "%.0f",
                       help: "Pause your open palm this long to arm; waves never pause, so never arm")
                slider("Arm: max drift while holding", $store.config.swipeArmMaxSpeed, 0.1...1.0, "%.2f")
            }
            Section("Displays") {
                Toggle("Model A: map hand to whole desktop", isOn: $store.config.useModelA)
                    .font(.caption)
                slider("Cross: overshoot", $store.config.crossOvershoot, 0.03...0.2, "%.2f",
                       help: "Push past the seam by this fraction of the display to cross")
                slider("Cross: dwell (ms)", $store.config.crossDwellMS, 150...800, "%.0f",
                       help: "…or hold any pressure against the seam this long")
                slider("Cross: re-cross lockout (ms)", $store.config.crossLockoutMS, 200...1500, "%.0f")
                slider("Anchor recenter rate", $store.config.anchorDecayRate, 0...8, "%.1f",
                       help: "How quickly reach recovers after a cross, scaled by hand speed")
            }
            Section("Windows") {
                Toggle("Practice on mock windows", isOn: $store.config.useMockWindows)
                    .font(.caption)
                Toggle("Raise window on grab", isOn: $store.config.raiseOnGrab)
                    .font(.caption)
                slider("AX write floor (ms)", $store.config.axWriteMinIntervalMS, 16...200, "%.0f",
                       help: "Minimum gap between window-position writes; slow apps auto-throttle above it")
                slider("Sticky hover margin (px)", $store.config.stickyHoverPx, 0...50, "%.0f",
                       help: "Pointer must exit the target window by this much before retargeting")
                readout("AX write latency", String(format: "%.1f ms", app.axLatencyMS))
            }
            Section("Spaces") {
                Toggle("Swipe switches Spaces (⌃←/⌃→)", isOn: $store.config.switchSpaces)
                    .font(.caption)
                Toggle("Thumb pose instead of swipe (fist + thumb sideways)", isOn: $store.config.thumbSwitch)
                    .font(.caption)
                slider("Thumb hold time (ms)", $store.config.thumbHoldMS, 100...800, "%.0f",
                       help: "Point your thumb at the Space you want; hold this long to fire")
                Toggle("Natural direction (hand pushes the desktop)", isOn: $store.config.swipeNatural)
                    .font(.caption)
                HStack {
                    Text("Accessibility")
                    Spacer()
                    Text(app.accessibilityOK ? "granted" : "NOT GRANTED")
                        .foregroundStyle(app.accessibilityOK ? .secondary : Color.orange)
                }
                if !app.accessibilityOK {
                    Text("The system prompt only opens Settings — you must flip the AirControl toggle there yourself.")
                        .font(.caption2).foregroundStyle(.orange)
                    Button("Open Accessibility settings") { SpaceSwitcher.openSystemSettings() }
                }
                slider("Post-switch freeze (ms)", $store.config.postSwipeSettleMS, 0...2000, "%.0f",
                       help: "Pointer + gestures pause while the Space slides")
                HStack {
                    Button("Test ⟵") { SpaceSwitcher.post(direction: -1) }
                    Spacer()
                    Button("Test ⟶") { SpaceSwitcher.post(direction: 1) }
                }
            }
            Section("Power") {
                Toggle("✌ turns AirControl off", isOn: $store.config.peaceOff)
                    .font(.caption)
                slider("Peace hold time (ms)", $store.config.peaceHoldMS, 400...2000, "%.0f",
                       help: "Index+middle up, ring+little folded; hold until the red meter fills")
            }
            Section("Live readouts") {
                readout("Detect FPS", String(format: "%.0f", app.stats.fps))
                readout("Pinch dist (raw / smooth)",
                        String(format: "%.2f / %.2f", app.stats.pinchRaw, app.stats.pinchSmooth))
                readout("Gesture", app.stats.pinching ? "PINCH"
                    : app.stats.swiping ? (app.stats.swipeArmed ? "palm ARMED" : "palm — arming…")
                    : "point")
                readout("Fingers extended", "\(app.stats.extendedCount)/4")
                HStack {
                    Text("Swipe progress")
                    Spacer()
                    ProgressView(value: abs(app.stats.swipeProgress))
                        .frame(width: 120)
                }
            }
            Section {
                Button("Reset to tuned defaults") { store.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ label: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ fmt: String,
                        help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
            if let help {
                Text(help).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func readout(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
