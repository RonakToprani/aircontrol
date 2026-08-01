import SwiftUI

@main
struct AirControlApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            Toggle("Enable AirControl", isOn: $state.enabled)
            Text(state.statusLine)
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
