import FluxCore
import SwiftUI

/// Barra de prompt flotante, centrada abajo.
struct PromptBarView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var focused: Bool
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !state.references.isEmpty {
                ReferenceTray()
            }
            TextField("Describe la imagen que quieres generar…", text: $state.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.horizontal, 6)
                .padding(.top, 4)

            HStack(spacing: 8) {
                Chip(icon: "photo", text: BFLEndpoint.flux3Image.displayName)
                    .help("Modelo")

                Button {
                    state.addReferences(chooseImages())
                } label: {
                    Chip(
                        icon: "square.on.square",
                        text: state.references.isEmpty ? "Referencias" : "Referencias · \(state.references.count)",
                        isActive: !state.references.isEmpty
                    )
                }
                .buttonStyle(.plain)
                .disabled(state.references.count >= 10)
                .help("Añade hasta 10 imágenes de referencia (también puedes arrastrarlas aquí)")

                ChipPicker(
                    icon: "aspectratio",
                    title: "Proporción",
                    options: Flux3Image.aspectRatios,
                    selection: $state.imageParams.aspectRatio,
                    label: { $0 == "auto" ? "Auto" : $0 }
                )

                ChipPicker(
                    icon: "viewfinder",
                    title: "Resolución",
                    options: Flux3Image.resolutions,
                    selection: $state.imageParams.resolution,
                    label: { Flux3Image.resolutionLabel($0) }
                )

                ChipPicker(
                    icon: "square.grid.2x2",
                    title: "Número de imágenes",
                    options: [1, 2, 3, 4],
                    selection: $state.imageParams.count,
                    label: { $0 == 1 ? "1 imagen" : "\($0) imágenes" }
                )

                Button { showSettings.toggle() } label: {
                    Chip(icon: "slider.horizontal.3", text: "Ajustes", isActive: showSettings)
                }
                .buttonStyle(.plain)
                .help("Tolerancia de seguridad y grounding")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    ImageSettingsPopover()
                        .environmentObject(state)
                }

                Spacer(minLength: 8)

                if state.isGenerating {
                    ProgressView().controlSize(.small)
                    Button("Cancelar") { state.cancelAllGenerations() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .help("Deja de esperar los resultados. BFL puede cobrar igualmente si ya habían empezado.")
                }

                Button { state.generateImage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.action.opacity(state.canGenerate ? 1 : 0.3)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!state.canGenerate)
                .help("Generar (⌘↩)")
            }
        }
        .padding(14)
        .frame(maxWidth: 820)
        .surfaceStyle(cornerRadius: Theme.cornerPromptBar)
        // Soltar imágenes sobre la barra = añadirlas como referencia.
        .dropDestination(for: URL.self) { urls, _ in
            state.addReferences(urls)
            return true
        }
        .padding(.horizontal, 28)
        .onAppear { focused = true }
    }
}

private struct ImageSettingsPopover: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SafetyToleranceControl(
                value: $state.imageParams.safety,
                range: SafetyTolerance.range(for: .flux3Image)
            )

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $state.imageParams.grounding) {
                    Text("Grounding (búsqueda externa)").font(.system(size: 13))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Text("Permite al modelo apoyarse en búsquedas web para sujetos reales.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("FLUX 3 Image no admite semilla (seed): cada petición da un resultado distinto.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 320)
    }
}
