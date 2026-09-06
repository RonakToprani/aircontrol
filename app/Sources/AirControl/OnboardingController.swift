import AppKit
import AVFoundation
import Combine
import SwiftUI

/// First-run welcome tour: a real window (not a panel) that walks a brand-new
/// user from "what is this" to "my hand just clicked something" in about two
/// minutes — permissions with live status, calibration, then an interactive
/// practice round where each gesture checks itself off when the ENGINE
/// actually detects it. Shown once automatically (aircontrol.onboarded flag),
/// reopenable from the menu bar any time.
final class OnboardingController: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?
    private let window: NSWindow
    private let model: OnboardingModel

    @MainActor
    override init() {
        model = OnboardingModel()
        let size = NSSize(width: 660, height: 560)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = "Welcome to AirControl"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
        window.center()
        super.init()
        window.delegate = self
        model.onFinish = { [weak self] in self?.window.close() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true) // menu-bar app: force ourselves front
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the tour at any point counts as "seen" — never nag again.
        UserDefaults.standard.set(true, forKey: "aircontrol.onboarded")
        model.teardown()
        onClose?()
    }
}

// MARK: -

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, camera, accessibility, calibrate, practice, done
    }

    /// The practice drills, in teaching order — every one must actually be
    /// PERFORMED to check off; Continue stays locked until all five are done.
    /// The ✌ off-switch is explained on a card, never practiced — it would
    /// turn the app off mid-tour.
    enum Drill: Int, CaseIterable {
        case move, grab, thumb, shaka, scroll
    }

    @Published var step: Step = .welcome {
        didSet {
            // Practice runs in a safe sandbox: two practice windows appear
            // (so a pinch can't grab your real windows), and Space switching
            // is suppressed (so the thumb drill can't yank you off this
            // desktop). Restored the moment practice ends, however it ends.
            if step == .practice { enterPracticeEnvironment() }
            else if oldValue == .practice { exitPracticeEnvironment() }
        }
    }
    @Published var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var handSeen = false
    @Published var axTrusted = SpaceSwitcher.isTrusted
    @Published var calibrated = false
    @Published var enabled = false
    @Published var mouseModeOn = false
    @Published var completed: Set<Drill> = []
    @Published var currentDrill: Drill = .move

    var onFinish: (() -> Void)?

    private let app = AppState.shared
    private var cancellables: Set<AnyCancellable> = []
    private var pollTimer: Timer?
    private var advancing = false
    private var lastPointer: CGPoint?
    private var travel: CGFloat = 0

    init() {
        calibrated = app.configStore.config.calibration != nil
        enabled = app.enabled
        mouseModeOn = app.configStore.config.mouseMode

        app.$handVisible
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                guard let self else { return }
                if visible { self.handSeen = true }
                self.maybeAdvanceCamera()
            }
            .store(in: &cancellables)

        app.$enabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.enabled = on }
            .store(in: &cancellables)

        app.$stats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in self?.observe(stats) }
            .store(in: &cancellables)

        app.configStore.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                guard let self else { return }
                // 🤙 drill: the shaka's observable effect IS the mode flip.
                if config.mouseMode != self.mouseModeOn {
                    self.mouseModeOn = config.mouseMode
                    // Only the ON flip counts: completing on an OFF flip would
                    // check the drill while stranding the scroll drill, which
                    // needs mouse mode to be on.
                    if self.step == .practice, self.currentDrill == .shaka,
                       config.mouseMode {
                        self.complete(.shaka)
                    }
                }
                if config.calibration != nil, !self.calibrated {
                    self.calibrated = true
                    if self.step == .calibrate { self.advance(after: 1.2) }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .aircontrolMockWindowDragged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Not gated on currentDrill: a drag performed in the moment
                // before the checklist advances to the grab row still counts
                // (the once-per-grab latch in the overlay would otherwise
                // swallow it, forcing a whole new grab).
                guard let self, self.step == .practice else { return }
                self.complete(.grab)
            }
            .store(in: &cancellables)

        // Permission states change outside our process — poll gently while
        // the tour is open (the only place the app ever polls anything).
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let cam = AVCaptureDevice.authorizationStatus(for: .video)
                if cam != self.cameraStatus { self.cameraStatus = cam }
                let trusted = SpaceSwitcher.isTrusted
                if trusted != self.axTrusted {
                    self.axTrusted = trusted
                    if trusted, self.step == .accessibility { self.advance(after: 0.8) }
                }
                self.maybeAdvanceCamera()
            }
        }
    }

    func teardown() {
        exitPracticeEnvironment() // closing mid-practice must not leak the sandbox
        pollTimer?.invalidate()
        pollTimer = nil
        cancellables.removeAll()
    }

    // MARK: practice sandbox

    private func enterPracticeEnvironment() {
        guard !app.practiceSandbox else { return }
        // A runtime overlay (AppState.effectiveConfig), never a config write:
        // nothing to restore, nothing that can leak to disk if the app dies
        // mid-practice, and the Tuning panel keeps showing real settings.
        app.practiceSandbox = true
        // Drills assume the session-start state (gesture mode): the 🤙 drill
        // must flip mouse mode ON, and the scroll drill builds on that.
        app.configStore.config.mouseMode = false
    }

    private func exitPracticeEnvironment() {
        guard app.practiceSandbox else { return }
        app.practiceSandbox = false
        // The shaka drill turned mouse mode on; the tour hands the user back
        // the same state every session starts in — mouse mode is ALWAYS a
        // deliberate, manual choice (Ronak's rule), never an ambient leftover.
        app.configStore.config.mouseMode = false
    }

    // MARK: actions

    func next() {
        guard let n = Step(rawValue: step.rawValue + 1) else { return }
        advancing = false
        step = n
    }

    func enableAirControl() {
        app.enabled = true
    }

    func openAccessibilitySettings() {
        SpaceSwitcher.openSystemSettings()
    }

    func startCalibration() {
        if !app.enabled { app.enabled = true }
        startedCalibration = true
        app.startCalibration()
    }
    @Published var startedCalibration = false

    func finish() {
        onFinish?() // closes the window; windowWillClose records "onboarded"
    }

    // MARK: auto-advance plumbing

    private func maybeAdvanceCamera() {
        guard step == .camera, cameraStatus == .authorized, handSeen else { return }
        advance(after: 0.8)
    }

    private func advance(after delay: TimeInterval) {
        guard !advancing else { return }
        advancing = true
        // Snapshot the step: if the user clicks Continue/Skip before this
        // fires, next() already moved on and a second next() would silently
        // skip a whole step (e.g. straight past Accessibility).
        let from = step
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.step == from else { return }
            self.next()
        }
    }

    private func observe(_ stats: GestureState) {
        guard step == .practice else { return }
        switch currentDrill {
        case .move:
            if app.handVisible {
                if let lp = lastPointer {
                    travel += hypot(stats.pointer.x - lp.x, stats.pointer.y - lp.y)
                }
                lastPointer = stats.pointer
                if travel > 0.9 { complete(.move) }
            }
        case .grab:
            break // completes on the mock-window drag notification
        case .thumb:
            // The pose fires its event even with Space switching suppressed —
            // the user performs the REAL gesture, the desktop just stays put.
            if stats.swipeEvent != nil { complete(.thumb) }
        case .shaka:
            break // detected on the config flip, not on stats
        case .scroll:
            if stats.scrollGrab { complete(.scroll) }
        }
    }

    private func complete(_ drill: Drill) {
        guard !completed.contains(drill) else { return }
        completed.insert(drill)
        if completed.count == Drill.allCases.count {
            advance(after: 1.2) // all five done — roll on to the cheat sheet
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            // First incomplete drill in teaching order — not blindly the next
            // raw value, since the grab can check off early (its notification
            // isn't gated on being the current row).
            if let n = Drill.allCases.first(where: { !self.completed.contains($0) }) {
                self.currentDrill = n
            }
        }
    }
}

// MARK: -

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            dots
                .padding(.top, 22)
            Spacer(minLength: 0)
            content
                .frame(maxWidth: 480)
                .padding(.horizontal, 40)
            Spacer(minLength: 0)
            footer
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
        .frame(minWidth: 660, minHeight: 560)
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= model.step.rawValue ? Color.teal : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: welcome
        case .camera: camera
        case .accessibility: accessibility
        case .calibrate: calibrate
        case .practice: practice
        case .done: done
        }
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to AirControl")
                .font(.system(size: 28, weight: .bold))
            Text("Control your Mac with your hand in the air — point, pinch, and scroll through the camera. Everything runs on your Mac; nothing is recorded or sent anywhere.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var camera: some View {
        stepPage(symbol: "web.camera",
                 title: "Turn on the camera",
                 text: "AirControl watches for your hand through the built-in camera. The video never leaves this Mac — it's processed live and thrown away.") {
            if model.cameraStatus == .denied {
                statusRow(ok: false, text: "Camera access denied — allow it in System Settings → Privacy & Security → Camera")
            } else if model.enabled && model.cameraStatus == .authorized {
                statusRow(ok: model.handSeen,
                          text: model.handSeen ? "Hand detected — you're on camera" : "Camera on — raise your hand so it can see you")
            } else {
                Button("Turn On AirControl") { model.enableAirControl() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
            }
        }
    }

    private var accessibility: some View {
        stepPage(symbol: "macwindow.and.cursorarrow",
                 title: "Allow Accessibility",
                 text: "This is how AirControl moves windows and clicks for you. The system dialog only opens Settings — flip the AirControl switch there, then come back.") {
            if model.axTrusted {
                statusRow(ok: true, text: "Accessibility granted")
            } else {
                VStack(spacing: 10) {
                    Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    statusRow(ok: false, text: "Waiting for the switch…")
                }
            }
        }
    }

    private var calibrate: some View {
        stepPage(symbol: "rectangle.dashed",
                 title: "Calibrate your reach",
                 text: "Pinch-hold at your comfortable top-left, then bottom-right. That small box becomes your whole desktop, so you never stretch. A preview window will guide you.") {
            if model.calibrated && !model.startedCalibration {
                statusRow(ok: true, text: "Already calibrated — recalibrate any time from the menu bar")
            } else if model.startedCalibration {
                statusRow(ok: model.calibrated,
                          text: model.calibrated ? "Calibrated" : "Follow the steps in the hand preview…")
            } else {
                Button("Calibrate Now") { model.startCalibration() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
            }
        }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Try it")
                .font(.system(size: 24, weight: .bold))
            Text(model.enabled
                 ? "Two practice windows just appeared on your desktop — they're safe to play with and vanish when you're done. Each move checks itself off when you actually do it."
                 : "Turn AirControl on from the menu bar to practice.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                drillRow(.move, symbol: "hand.raised", title: "Move the cursor",
                         hint: "Open hand, move it around")
                drillRow(.grab, symbol: "macwindow", title: "Grab a practice window",
                         hint: "Pinch on a practice window, drag it somewhere new, let go")
                drillRow(.thumb, symbol: "hand.point.left", title: "Point your thumb between desktops",
                         hint: "Fist, thumb out sideways, hold — practicing here won't switch anything")
                drillRow(.shaka, symbol: "hand.wave", title: "Shaka 🤙 for mouse mode",
                         hint: "Palm facing you — thumb + little finger out, hold until the meter fills")
                drillRow(.scroll, symbol: "scroll", title: "Fist to scroll",
                         hint: model.mouseModeOn ? "Close your fist (thumb tucked) and move — watch the Scroll practice window"
                                                 : "Needs mouse mode — do the 🤙 first")
            }
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.slash")
                    .foregroundStyle(.secondary)
                Text("To turn AirControl off: hold a peace sign ✌ until the red meter fills.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.teal)
            Text("You're set")
                .font(.system(size: 28, weight: .bold))
            VStack(alignment: .leading, spacing: 6) {
                cheat("Open hand", "move the cursor")
                cheat("Pinch", "click · hold to drag windows")
                cheat("🤙 hold, palm facing you", "mouse mode on / off")
                cheat("Fist (thumb in)", "scroll · in mouse mode")
                cheat("Pinch-hold a text box", "dictate · release to type · 👍 to send")
                cheat("Fist + thumb sideways", "switch desktop")
                cheat("✌ hold", "turn off")
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            Text("Everything — speeds, hold times, thresholds — is adjustable in Advanced Tuning.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: pieces

    private func stepPage(symbol: String, title: String, text: String,
                          @ViewBuilder action: () -> some View) -> some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.teal)
            Text(title)
                .font(.system(size: 26, weight: .bold))
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
                .padding(.top, 6)
        }
    }

    private func statusRow(ok: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(ok ? Color.teal : Color.secondary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func drillRow(_ drill: OnboardingModel.Drill, symbol: String,
                          title: String, hint: String) -> some View {
        let isDone = model.completed.contains(drill)
        let isCurrent = model.currentDrill == drill && !isDone
        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 28)
                .foregroundStyle(isCurrent ? Color.teal : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isDone ? Color.teal : Color.secondary.opacity(0.4))
                .animation(.spring(duration: 0.35), value: isDone)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isCurrent ? Color.teal.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func cheat(_ gesture: String, _ action: String) -> some View {
        HStack(spacing: 8) {
            Text(gesture)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 190, alignment: .trailing)
            Text(action)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if model.step == .practice || model.step == .accessibility || model.step == .calibrate {
                Button(model.step == .practice ? "Skip demo" : "Skip for now") { model.next() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch model.step {
            case .welcome:
                Button("Get Started") { model.next() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .keyboardShortcut(.defaultAction)
            case .done:
                Button("Finish") { model.finish() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .keyboardShortcut(.defaultAction)
            case .practice:
                // Doing beats reading: Continue unlocks only when all five
                // drills were actually performed. "Skip demo" stays as the out.
                Button("Continue") { model.next() }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.completed.count < OnboardingModel.Drill.allCases.count)
            default:
                Button("Continue") { model.next() }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
