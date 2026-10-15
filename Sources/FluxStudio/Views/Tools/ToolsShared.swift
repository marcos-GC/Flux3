import AppKit
import FluxCore
import SwiftUI

/// Barra flotante inferior de las herramientas.
struct ToolBarContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: 900)
            .surfaceStyle(cornerRadius: Theme.cornerPromptBar)
            .padding(.horizontal, 28)
    }
}

/// Botón circular negro de generar, con estado y cancelación.
struct ToolGenerateControls: View {
    @ObservedObject var runner: ToolRunner
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if runner.isRunning {
                ProgressView().controlSize(.small)
                Text(runner.status).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Button("Cancelar") { runner.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }
            Button(action: action) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.action.opacity(enabled && !runner.isRunning ? 1 : 0.3)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!enabled || runner.isRunning)
            .help("Generar (⌘↩)")
        }
    }
}

/// Chip "Ajustes" con tolerancia de seguridad, formato y (opcional) semilla.
struct ToolSettingsChip<Extra: View>: View {
    @ObservedObject var model: BaseToolModel
    var showsSeed = true
    @ViewBuilder var extra: () -> Extra
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Chip(icon: "slider.horizontal.3", text: "Ajustes", isActive: isOpen)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                SafetyToleranceControl(value: $model.safety, range: SafetyTolerance.range(for: model.endpoint))
                HStack {
                    SectionLabel("Formato de salida")
                    Spacer()
                    Picker("", selection: $model.format) {
                        ForEach(ToolOutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
                if showsSeed {
                    HStack {
                        SectionLabel("Semilla")
                        Spacer()
                        TextField("Aleatoria", text: $model.seedText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    Text("Con la misma semilla y los mismos datos, el resultado se repite.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                extra()
            }
            .padding(16)
            .frame(width: 340)
        }
    }
}

extension ToolSettingsChip where Extra == EmptyView {
    init(model: BaseToolModel, showsSeed: Bool = true) {
        self.init(model: model, showsSeed: showsSeed, extra: { EmptyView() })
    }
}

/// Mientras se prepara la imagen seleccionada para una herramienta.
struct ToolLoadingView: View {
    let isLoading: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 8) {
            if let error {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 22))
                Text(error).font(.system(size: 12)).multilineTextAlignment(.center)
            } else {
                ProgressView()
                Text("Preparando la imagen…").font(.system(size: 12))
            }
        }
        .foregroundStyle(error == nil ? Theme.textSecondary : Theme.danger)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Tamaño de una imagen ajustada (sin recortar) a un espacio.
func fittedSize(_ image: CGSize, in container: CGSize) -> CGSize {
    guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else { return .zero }
    let scale = min(container.width / image.width, container.height / image.height)
    return CGSize(width: image.width * scale, height: image.height * scale)
}
