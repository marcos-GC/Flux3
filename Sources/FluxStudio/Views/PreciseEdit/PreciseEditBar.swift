import FluxCore
import SwiftUI

/// Barra inferior: chips de regiones, cambio global, referencias, ver prompt y generar.
struct PreciseEditBar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var model: PreciseEditModel
    @Binding var showPrompt: Bool
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.regions.isEmpty || !model.extraReferences.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.regions.enumerated()), id: \.element.id) { index, region in
                            Button { model.selectedRegionID = region.id; model.showRegions = true } label: {
                                HStack(spacing: 6) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 16, height: 16)
                                        .background(Circle().fill(region.kind == .anchor ? Color(hex: 0x3F9D6B) : Theme.region))
                                    Text(region.displayText)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .frame(maxWidth: 180, alignment: .leading)
                                    if region.reference != nil {
                                        Image(systemName: "photo").font(.system(size: 10))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(model.selectedRegionID == region.id ? Theme.region.opacity(0.14) : Color.white.opacity(0.7)))
                                .overlay(Capsule().strokeBorder(Theme.border))
                                .foregroundStyle(Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(model.extraReferences) { reference in
                            ExtraReferenceChip(reference: reference)
                        }
                    }
                }
            }

            TextField("Cambio en toda la imagen (opcional)", text: $model.globalInstruction, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(.horizontal, 6)

            HStack(spacing: 8) {
                Button {
                    model.addExtraReferences(chooseImages())
                } label: {
                    Chip(icon: "photo.badge.plus", text: "Añadir referencia")
                }
                .buttonStyle(.plain)
                .help("Imágenes extra que el modelo puede usar (se citan como ref_image_N)")

                ChipPicker(
                    icon: "viewfinder", title: "Resolución", options: Flux3Image.resolutions,
                    selection: $model.resolution, label: { Flux3Image.resolutionLabel($0) }
                )
                ChipPicker(
                    icon: "square.grid.2x2", title: "Número de resultados", options: [1, 2, 3, 4],
                    selection: $model.count, label: { $0 == 1 ? "1 resultado" : "\($0) resultados" }
                )
                Button { showSettings.toggle() } label: {
                    Chip(icon: "slider.horizontal.3", text: "Ajustes", isActive: showSettings)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 14) {
                        SafetyToleranceControl(value: $model.safety, range: SafetyTolerance.range(for: .flux3Image))
                        Toggle("Grounding (búsqueda externa)", isOn: $model.grounding)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .padding(16)
                    .frame(width: 320)
                }

                Button { showPrompt = true } label: {
                    Chip(icon: "text.alignleft", text: model.manualPrompt == nil ? "Ver prompt" : "Ver prompt (editado)",
                         isActive: model.manualPrompt != nil)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                if model.isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(model.statusText).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    }
                    Button("Cancelar") { model.cancelGeneration() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }

                Button { model.generate(using: state) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.action.opacity(canGenerate ? 1 : 0.3)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canGenerate)
                .help("Generar (⌘↩)")
            }
        }
        .padding(14)
        .frame(maxWidth: 860)
        .surfaceStyle(cornerRadius: Theme.cornerPromptBar)
        .padding(.horizontal, 28)
        .onChange(of: model.safety) {
            model.safety = SafetyTolerance.clamp(model.safety, for: .flux3Image)
        }
    }

    private var canGenerate: Bool {
        !model.isGenerating && model.hasSomethingToDo && !model.referencesBusy
    }
}

private struct ExtraReferenceChip: View {
    @EnvironmentObject private var model: PreciseEditModel
    let reference: EditReference

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Color(hex: 0xE2E2E2)
                if let thumb = reference.thumbnail { Image(nsImage: thumb).resizable().scaledToFill() }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text("Ref. extra").font(.system(size: 11))
            Button {
                model.extraReferences.removeAll { $0.id == reference.id }
            } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.7)))
        .overlay(Capsule().strokeBorder(reference.error == nil ? Theme.border : Theme.danger))
        .help(reference.error ?? reference.url.lastPathComponent)
    }
}

/// "Ver prompt": Resumen y Prompt del modelo (editable).
struct PromptPreviewSheet: View {
    @EnvironmentObject private var model: PreciseEditModel
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("", selection: $tab) {
                    Text("Resumen").tag(0)
                    Text("Prompt del modelo").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Spacer()
                Button("Cerrar") { save(); dismiss() }.keyboardShortcut(.cancelAction)
            }

            if tab == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Cambio en toda la imagen")
                        Text(model.globalInstruction.isEmpty ? "—" : model.globalInstruction)
                            .font(.system(size: 13))
                        SectionLabel("Regiones").padding(.top, 6)
                        if model.regions.isEmpty {
                            Text("No hay regiones.").foregroundStyle(Theme.textSecondary)
                        }
                        let specs = model.specs
                        ForEach(Array(model.regions.enumerated()), id: \.element.id) { index, region in
                            let spec = specs[index]
                            let src = spec.source.map { PreciseEdit.bbox($0, imageWidth: size.width, imageHeight: size.height) }
                            let tgt = spec.target.map { PreciseEdit.bbox($0, imageWidth: size.width, imageHeight: size.height) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(spec.number). \(region.kind.spanishName) — \(region.displayText)")
                                    .font(.system(size: 13, weight: .medium))
                                Text([src.map { "origen \($0)" }, tgt.map { "destino \($0)" }, region.reference.map { _ in "con imagen de referencia" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Theme.textSecondary)
                                if !spec.isUsable {
                                    Text("No se enviará: falta la instrucción.")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.danger)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Este es el texto exacto que se enviará. Puedes editarlo a mano antes de generar.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                TextEditor(text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
                HStack {
                    Button("Copiar") { copyText(draft) }
                    if model.manualPrompt != nil || draft != model.automaticPrompt {
                        Button("Volver al automático") {
                            model.manualPrompt = nil
                            draft = model.automaticPrompt
                        }
                    }
                    Spacer()
                    if model.manualPrompt != nil {
                        Label("Editado a mano: ya no se actualiza al cambiar las regiones", systemImage: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 720, height: 520)
        .background(Theme.background)
        .preferredColorScheme(.light)
        .onAppear { draft = model.effectivePrompt }
        .onDisappear(perform: save)
    }

    private var size: CGSize { model.current?.pixelSize ?? CGSize(width: 1000, height: 1000) }

    private func save() {
        model.manualPrompt = draft == model.automaticPrompt ? nil : draft
    }
}
