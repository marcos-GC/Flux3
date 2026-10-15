import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

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
            Text("Se quitan el prompt, las referencias y la imagen seleccionada. Los resultados siguen en la tira y en el Historial.")
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
        default:
            WorkspaceView()
        }
    }
}

