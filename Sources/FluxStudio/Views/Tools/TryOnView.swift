import FluxCore
import SwiftUI

/// Probador virtual: persona + prenda + prompt.
struct TryOnView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: TryOnModel
    @ObservedObject private var runner: ToolRunner
    @State private var editPrompt = false

    init(model: TryOnModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Probador virtual", subtitle: "Viste a la persona con la prenda u objeto de la segunda imagen.") {
                if model.input != nil || model.garment != nil {
                    Button("Empezar de nuevo") { model.reset() }
                }
            }

            HStack(spacing: 18) {
                VStack(spacing: 14) {
                    slot(title: "Persona", subtitle: "Imagen 1", image: model.input?.image, loading: model.isLoading) {
                        model.load($0)
                    }
                    slot(title: "Prenda", subtitle: "Imagen 2", image: model.garment?.image, loading: model.garmentLoading) {
                        model.loadGarment($0)
                    }
                }
                .frame(width: 260)

                Group {
                    if runner.current != nil {
                        ToolResultView(runner: runner, before: model.input?.image) { model.useCurrentResultAsInput() }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "tshirt").font(.system(size: 30, weight: .light))
                            Text("El resultado aparecerá aquí").font(.system(size: 13))
                        }
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface.opacity(0.6)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 12)

            if let error = model.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger).padding(.bottom, 6)
            }

            ToolBarContainer {
                if editPrompt {
                    TextField("Prompt", text: Binding(
                        get: { model.prompt },
                        set: { model.customPrompt = $0 }
                    ), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1...4)
                    .padding(.horizontal, 6)
                } else {
                    TextField("Describe la prenda en inglés (p. ej. «oversized denim jacket», «red Nike hoodie»)",
                              text: $model.garmentDescription)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 6)
                    Text(model.prompt)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button {
                        editPrompt.toggle()
                        if !editPrompt { model.customPrompt = nil }
                    } label: {
                        Chip(icon: "pencil", text: editPrompt ? "Usar la fórmula de BFL" : "Editar prompt", isActive: editPrompt)
                    }
                    .buttonStyle(.plain)
                    Text("Describe solo la prenda: la cara, la pose y el fondo se mantienen solos.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ToolSettingsChip(model: model)
                    ToolGenerateControls(runner: runner, enabled: model.input != nil && model.garment != nil) {
                        model.generate(state: state)
                    }
                }
            }
        }
        .onAppear(perform: takeHandoff)
        .onChange(of: state.handoff) { takeHandoff() }
    }

    @ViewBuilder
    private func slot(title: String, subtitle: String, image: NSImage?, loading: Bool, onPick: @escaping (URL) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                Spacer()
                if image != nil {
                    Button("Cambiar") {
                        if let url = chooseImages(allowsMultiple: false).first { onPick(url) }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                }
            }
            Group {
                if let image {
                    FittedImage(image: image)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard let url = urls.first(where: ReferenceImage.isSupported) else { return false }
                            onPick(url)
                            return true
                        }
                } else if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ToolDropZone(title: "Subir", subtitle: "o arrastra", compact: true, onPick: onPick)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func takeHandoff() {
        guard let handoff = state.handoff, handoff.mode == .tryOn else { return }
        model.load(handoff.fileURL)
        state.handoff = nil
    }
}
