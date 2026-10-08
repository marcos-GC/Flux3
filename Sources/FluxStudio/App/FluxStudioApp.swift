import AppKit
import SwiftUI

@main
struct FluxStudioApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var state: AppState

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _state = StateObject(wrappedValue: AppState(settings: settings))
        // Necesario si se lanza con `swift run` (fuera de un .app).
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("FLUX Studio") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(state)
                .environmentObject(state.history)
                .environmentObject(state.preciseEdit)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
