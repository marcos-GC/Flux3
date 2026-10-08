import FluxCore
import SwiftUI

/// Barra inferior del Probador virtual: la persona es la imagen seleccionada; aquí se elige la prenda.
struct TryOnBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: TryOnModel
    @ObservedObject private var runner: ToolRunner
    @State private var editPrompt = false
    @State private var isDropTarget = false

    init(model: TryOnModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        ToolBarContainer {
            HStack(alignment: .top, spacing: 12) {
                garmentSlot
                VStack(alignment: .leading, spacing: 6) {
                    if editPrompt {
                        TextField("Prompt", text: Binding(
                            get: { model.prompt },
                            set: { model.customPrompt = $0 }
                        ), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1...4)
                    } else {
                        TextField("Describe la prenda en inglés (p. ej. «oversized denim jacket»)", text: $model.garmentDescription)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                        Text(model.prompt)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    editPrompt.toggle()
                    if !editPrompt { model.customPrompt = nil }
                } label: {
                    Chip(icon: "pencil", text: editPrompt ? "Usar la fórmula de BFL" : "Editar prompt", isActive: editPrompt)
                }
                .buttonStyle(.plain)
                Text("La persona es la imagen seleccionada. Describe solo la prenda.")
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

    private var garmentSlot: some View {
        Button {
            if let url = chooseImages(allowsMultiple: false).first { model.loadGarment(url) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(isDropTarget ? Theme.region.opacity(0.1) : Color.white.opacity(0.7))
                if let garment = model.garment {
                    Image(nsImage: garment.image).resizable().scaledToFill()
                } else if model.garmentLoading {
                    ProgressView().controlSize(.small)
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: "tshirt").font(.system(size: 16))
                        Text("Prenda").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isDropTarget ? Theme.region : Theme.border,
                                                                      style: StrokeStyle(lineWidth: 1, dash: model.garment == nil ? [4, 3] : [])))
        }
        .buttonStyle(.plain)
        .help("Imagen 2: la prenda u objeto (haz clic o arrastra una imagen)")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: ReferenceImage.isSupported) else { return false }
            model.loadGarment(url)
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}
