import SwiftUI

@main
struct AirControlApp: App {
    @StateObject private var state = AppState.shared
    @StateObject private var config = AppState.shared.configStore

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enable AirControl", isOn: $state.enabled)
            Text(state.statusLine)
            if state.needsAccessibility {
                Text("⚠︎ Needs Accessibility permission")
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
