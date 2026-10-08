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
                                        .background(Circle().fill(Theme.regionColor(index, kind: region.kind)))
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
                                .background(Capsule().fill(model.selectedRegionID == region.id ? Theme.regionColor(index, kind: region.kind).opacity(0.16) : Color.white.opacity(0.7)))
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

                Button { showPrompt.toggle() } label: {
                    Chip(icon: "text.alignleft", text: model.manualPrompt == nil ? "Ver prompt" : "Ver prompt (editado)",
                         isActive: showPrompt || model.manualPrompt != nil)
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

/// Panel "Ver prompt" encima de la barra: Resumen y Prompt del modelo (editable).
struct PromptPanel: View {
    @EnvironmentObject private var model: PreciseEditModel
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                tabButton("Resumen", 0)
                tabButton("Prompt del modelo", 1)
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .help("El prompt del modelo es el texto exacto que se envía. Puedes editarlo a mano.")
                Spacer()
                if tab == 1 {
                    if model.manualPrompt != nil {
                        Text("Editado a mano").font(.system(size: 11)).foregroundStyle(Theme.danger)
                        Button("Volver al automático") { model.manualPrompt = nil }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                    }
                    Button("Copiar") { copyText(model.effectivePrompt) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                }
            }

            Group {
                if tab == 0 { summary } else { editor }
            }
            .frame(height: 150)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .padding(14)
        .frame(maxWidth: 820)
        .surfaceStyle(cornerRadius: 18)
        .padding(.horizontal, 40)
    }

    private func tabButton(_ title: String, _ index: Int) -> some View {
        Button { tab = index } label: {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(tab == index ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(tab == index ? Theme.textPrimary : Theme.border))
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    pill(Text("TODA LA IMAGEN"))
                    Text(model.globalInstruction.isEmpty ? "Sin cambio para toda la imagen" : model.globalInstruction)
                        .font(.system(size: 13))
                        .foregroundStyle(model.globalInstruction.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                }
                let specs = model.specs
                ForEach(Array(model.regions.enumerated()), id: \.element.id) { index, region in
                    HStack(spacing: 10) {
                        pill(HStack(spacing: 5) {
                            Text("\(index + 1)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Theme.regionColor(index, kind: region.kind)))
                            Text(region.kind == .edit ? "REGIÓN" : region.kind.spanishName.uppercased())
                        })
                        Text(region.displayText).font(.system(size: 13))
                        if region.reference != nil {
                            Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        }
                        if !specs[index].isUsable {
                            Text("no se enviará").font(.system(size: 11)).foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pill<Content: View>(_ content: Content) -> some View {
        content
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(Theme.border))
    }

    private var editor: some View {
        TextEditor(text: Binding(
            get: { model.effectivePrompt },
            set: { model.manualPrompt = $0 == model.automaticPrompt ? nil : $0 }
        ))
        .font(.system(size: 12, design: .monospaced))
        .scrollContentBackground(.hidden)
    }
}
