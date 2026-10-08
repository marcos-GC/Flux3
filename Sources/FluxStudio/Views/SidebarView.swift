import FluxCore
import SwiftUI

/// Barra lateral: herramientas del Estudio arriba; Historial y Ajustes abajo.
struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 4) {
            // Hueco para los botones de la ventana (barra de título oculta).
            Spacer().frame(height: 34)

            Text("F")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.action))
                .padding(.bottom, 14)
                .help("FLUX Studio")

            ForEach(WorkspaceTool.allCases) { tool in
                let disabled = tool.needsImage && state.focusedURL == nil
                SidebarItem(
                    icon: tool.icon,
                    title: tool.title,
                    isSelected: state.mode == .generate && state.tool == tool,
                    disabled: disabled,
                    help: disabled ? "\(tool.help). Selecciona o genera una imagen primero." : tool.help
                ) {
                    state.tool = tool
                    state.mode = .generate
                }
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

            SidebarItem(icon: AppMode.history.icon, title: AppMode.history.title,
                        isSelected: state.mode == .history, help: "Todo lo generado") { state.mode = .history }
            SidebarItem(icon: AppMode.settings.icon, title: AppMode.settings.title,
                        isSelected: state.mode == .settings, help: "API key, región y carpeta") { state.mode = .settings }
        }
        .padding(.vertical, 14)
        .frame(width: 78)
        .frame(maxHeight: .infinity)
        .background(Theme.surface)
    }
}

func formatCredits(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "es_ES")))
}

private struct SidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var disabled = false
    var help = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.white : (disabled ? Theme.textSecondary.opacity(0.45) : Theme.textPrimary))
            .frame(width: 64, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Theme.action : (hovering && !disabled ? Color.white.opacity(0.8) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}
