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
            CommandGroup(replacing: .newItem) {
                Button("Nuevo") { state.requestNew() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Asistente de prompts") {
                    state.assistant.isOpen.toggle()
                    if state.assistant.isOpen { state.mode = .generate }
                }
                .keyboardShortcut("l", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copiar prompt y parámetros") {
                    if let url = state.focusedURL { state.copyRecipe(from: url) }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Pegar prompt y parámetros") { state.pasteRecipe() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Button("Guardar prompt en Prompts guardados…") { state.saveCurrentRecipe() }
                    .keyboardShortcut("s", modifiers: [.command, .option])
            }
        }
    }
}
