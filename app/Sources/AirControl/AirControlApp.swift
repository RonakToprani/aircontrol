import SwiftUI

/// Quit safety: a MenuBarExtra app has no window whose close we could hook,
/// so this is the only spot that guarantees a quit mid-pinch doesn't strand
/// a synthetic mouse button DOWN or leave the system cursor hidden — both
/// outlive the process (the cursor is hidden via a CGS connection property).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.prepareForTermination()
    }
}

@main
struct AirControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared
    @StateObject private var config = AppState.shared.configStore

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enable AirControl", isOn: $state.enabled)
            Text(state.statusLine)
            if state.needsAccessibility {
                // A warning you can't act on is a dead end — clicking jumps
                // straight to the pane where the checkbox lives.
                Button("⚠︎ Grant Accessibility permission…") {
                    SpaceSwitcher.openSystemSettings()
                }
            }
            Divider()
            Toggle("Mouse mode — pinch to click", isOn: $config.config.mouseMode)
            Divider()
            Button("Welcome Tour…") { state.showOnboarding() }
            Button("Calibrate hand range…") { state.startCalibration() }
                .disabled(!state.enabled)
            Divider()
            Toggle("Show hand preview", isOn: $state.showPreview)
                .disabled(!state.enabled)
            Toggle("Advanced Tuning…", isOn: $state.showTuning)
                .disabled(!state.enabled)
            Divider()
            Toggle("Start at Login", isOn: Binding(
                get: { LoginItem.enabled },
                set: { LoginItem.enabled = $0 }))
            Button("Check for Updates…") { UpdateChecker.check() }
            Button("Quit AirControl") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            // The icon is the app's identity — it NEVER changes with mode,
            // only fills in while enabled. Mode feedback lives in the HUD.
            Image(systemName: state.enabled ? "hand.raised.fill" : "hand.raised")
        }
    }
}
