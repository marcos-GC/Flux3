import FluxCore
import SwiftUI

/// Barra inferior de «Pintar y rellenar»: pincel, qué poner en la zona pintada y referencia opcional.
struct FillBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: FillModel
    @ObservedObject private var runner: ToolRunner
    @State private var showPrompt = false
    @State private var isDropTarget = false

    init(model: FillModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        ToolBarContainer {
            MaskBrushControls(model: model, paintHelp: "la zona que quieres cambiar")

            HStack(alignment: .top, spacing: 12) {
                referenceSlot
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Qué quieres en la zona pintada (mejor en inglés, p. ej. «a green velvet armchair»)",
                              text: $model.prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1...4)
                    if showPrompt {
                        Text(model.sentPrompt ?? "Pinta primero la zona que quieres cambiar.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                }
            }

            HStack(spacing: 8) {
                Button { showPrompt.toggle() } label: {
                    Chip(icon: "text.alignleft", text: "Ver prompt", isActive: showPrompt)
                }
                .buttonStyle(.plain)
                .help("El texto exacto que se envía a FLUX 3 Image")
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(model.isEraser && model.maskIsEmpty ? Theme.danger : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                ToolSettingsChip(model: model, showsSeed: false) { fillSettings }
                ToolGenerateControls(runner: runner, enabled: model.canGenerate) { model.generate(state: state) }
            }
        }
    }

    private var hint: String {
        if model.maskIsEmpty {
            return model.isEraser
                ? "«Desmarcar» solo quita pintura violeta. Usa «Marcar» para señalar la zona."
                : "Pinta en violeta la zona que quieres cambiar y describe qué poner."
        }
        if model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Describe qué quieres en la zona pintada."
        }
        return model.pasteOnlyMask ? "Solo cambiará lo pintado; el resto queda igual." : "Se guardará la imagen entera que devuelva FLUX."
    }

    @ViewBuilder
    private var fillSettings: some View {
        HStack {
            SectionLabel("Resolución")
            Spacer()
            Picker("", selection: $model.resolution) {
                ForEach(Flux3Image.resolutions, id: \.self) { Text(Flux3Image.resolutionLabel($0)).tag($0) }
            }
            .labelsHidden()
            .frame(width: 160)
        }
        Toggle("Pegar solo en la zona pintada", isOn: $model.pasteOnlyMask)
            .font(.system(size: 12))
            .help("Del resultado de FLUX solo se copia lo pintado sobre tu foto: el resto queda idéntico")
        if model.pasteOnlyMask {
            sliderRow("Ampliar zona", value: $model.grow, range: 0...30,
                      help: "Agranda la zona pintada al pegar para que no quede un hueco en el borde")
            sliderRow("Suavizar borde", value: $model.feather, range: 0...60,
                      help: "Anchura de la transición entre el resultado y tu foto. Si se nota la costura, súbelo")
            Text("Medidas para una foto de unos 2000 px; se ajustan al tamaño real.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, help: String) -> some View {
        HStack {
            SectionLabel(title)
            Spacer()
            Slider(value: value, in: range, step: 1).frame(width: 130)
            Text("\(Int(value.wrappedValue)) px")
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 40, alignment: .leading)
        }
        .help(help)
    }

    private var referenceSlot: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if let url = chooseImages(allowsMultiple: false).first { model.loadReference(url) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(isDropTarget ? Theme.region.opacity(0.1) : Color.white.opacity(0.7))
                    if let reference = model.reference {
                        Image(nsImage: reference.image).resizable().scaledToFill()
                    } else if model.referenceLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        VStack(spacing: 3) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 15))
                            Text("Referencia").font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
                    isDropTarget ? Theme.region : Theme.border,
                    style: StrokeStyle(lineWidth: 1, dash: model.reference == nil ? [4, 3] : [])))
            }
            .buttonStyle(.plain)
            .help("Opcional: imagen de lo que quieres poner en la zona pintada (haz clic o arrastra una imagen)")
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: ReferenceImage.isSupported) else { return false }
                model.loadReference(url)
                return true
            } isTargeted: { isDropTarget = $0 }

            if model.reference != nil {
                Button { model.reference = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .help("Quitar la referencia")
            }
        }
    }
}
