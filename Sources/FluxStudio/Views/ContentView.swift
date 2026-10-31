import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var clipboardMonitor: Any?

    private var pastePrompt: Binding<Bool> {
        Binding(get: { !state.pendingPaste.isEmpty }, set: { if !$0 { state.pendingPaste = [] } })
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(Theme.border).frame(width: 1)
            ZStack {
                Theme.background
                mainView
            }
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .frame(minWidth: 1000, minHeight: 720)
        .preferredColorScheme(.light)
        .tint(Theme.textPrimary)
        .confirmationDialog("¿Empezar de cero?", isPresented: $state.confirmNew) {
            Button("Empezar de cero", role: .destructive) { state.startFresh() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se quitan el prompt, las referencias y la imagen seleccionada. Lo que se esté generando sigue por detrás y aparecerá en la tira; los resultados siguen en el Historial.")
        }
        .confirmationDialog(
            state.pendingPaste.count > 1 ? "¿Qué hacemos con las \(state.pendingPaste.count) imágenes pegadas?" : "¿Qué hacemos con la imagen pegada?",
            isPresented: pastePrompt
        ) {
            Button("Editar esta imagen") {
                let urls = state.pendingPaste
                state.pendingPaste = []
                state.receive(urls, as: .edit)
            }
            Button("Usar como referencia") {
                let urls = state.pendingPaste
                state.pendingPaste = []
                state.receive(urls, as: .reference)
            }
            Button("Cancelar", role: .cancel) { state.pendingPaste = [] }
        } message: {
            Text("Editar la abre en grande para escribir el cambio o dibujar regiones. Como referencia se añade a la caja del prompt («image 1, 2…») para generar algo nuevo.")
        }
        .sheet(item: $state.recipeDraft) { draft in
            RecipeEditorSheet(draft: draft) { state.recipeDraft = nil }
                .environmentObject(state)
        }
        // Aviso breve (prompt copiado, guardado…).
        .overlay(alignment: .bottom) {
            if let notice = state.notice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .surfaceStyle(cornerRadius: 16)
                    .padding(.bottom, 120)
                    .transition(.opacity)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(3))
                        if state.notice == notice { state.notice = nil }
                    }
            }
        }
        .animation(.easeOut(duration: 0.2), value: state.notice)
        .onAppear {
            if clipboardMonitor == nil { clipboardMonitor = Clipboard.installMonitor(state: state) }
        }
        .onDisappear {
            if let clipboardMonitor { NSEvent.removeMonitor(clipboardMonitor) }
            clipboardMonitor = nil
        }
        .alert(item: $state.alert) { alert in
            if alert.opensSettings {
                return Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    primaryButton: .default(Text("Abrir Ajustes")) { state.mode = .settings },
                    secondaryButton: .cancel(Text("Cerrar"))
                )
            }
            return Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }

    @ViewBuilder
    private var mainView: some View {
        switch state.mode {
        case .settings:
            SettingsView()
        case .history:
            HistoryView()
        case .library:
            PromptLibraryView(library: state.library)
        default:
            WorkspaceView()
        }
    }
}

