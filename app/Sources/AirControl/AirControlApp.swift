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
            Button("Calibrate hand range…") { state.startCalibration() }
                .disabled(!state.enabled)
            Button("Reset calibration") { state.resetCalibration() }
            Divider()
            Toggle("Show hand preview", isOn: $state.showPreview)
                .disabled(!state.enabled)
            Toggle("Show tuning panel", isOn: $state.showTuning)
                .disabled(!state.enabled)
            Divider()
            Button("Quit AirControl") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: state.enabled ? "hand.raised.fill" : "hand.raised")
        }
    }
}
