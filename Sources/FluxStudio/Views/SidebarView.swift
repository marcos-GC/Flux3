import FluxCore
import SwiftUI

/// Barra lateral fina con iconos para cambiar de modo.
struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 6) {
            // Hueco para los botones de la ventana (barra de título oculta).
            Spacer().frame(height: 34)

            Text("F")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.action))
                .padding(.bottom, 12)
                .help("FLUX Studio")

            ForEach(AppMode.tools) { mode in
                SidebarButton(mode: mode, isSelected: state.mode == mode) { state.mode = mode }
            }

            Spacer()

            if state.sessionCredits > 0 {
                VStack(spacing: 1) {
                    Text(formatCredits(state.sessionCredits))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                    Text("créditos")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.textPrimary)
                .help("Créditos gastados en esta sesión")
                .padding(.bottom, 6)
            }

            SidebarButton(mode: .history, isSelected: state.mode == .history) { state.mode = .history }
            SidebarButton(mode: .settings, isSelected: state.mode == .settings) { state.mode = .settings }
        }
        .padding(.vertical, 14)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}

func formatCredits(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "es_ES")))
}

private struct SidebarButton: View {
    let mode: AppMode
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: mode.icon)
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.white : (hovering ? Color.white.opacity(0.6) : .clear))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Theme.border : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(mode.title)
    }
}
