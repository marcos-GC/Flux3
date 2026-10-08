import FluxCore
import SwiftUI

/// Outpainting: la imagen dentro de un lienzo mayor; se arrastra para colocarla.
struct OutpaintView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: OutpaintModel
    @ObservedObject private var runner: ToolRunner
    @State private var showResult = true

    init(model: OutpaintModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Outpainting", subtitle: "Amplía la imagen más allá de sus bordes.") {
                if model.input != nil {
                    if runner.current != nil {
                        Picker("", selection: $showResult) {
                            Text("Lienzo").tag(false)
                            Text("Resultado").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    Button("Cambiar imagen") { model.reset() }
                }
            }

            Group {
                if let input = model.input {
                    if showResult && runner.current != nil {
                        ToolResultView(runner: runner, before: nil, comparable: false) {
                            model.useCurrentResultAsInput()
                            showResult = false
                        }
                    } else {
                        OutpaintCanvas(model: model, input: input)
                    }
                } else if model.isLoading {
                    ProgressView()
                } else {
                    ToolDropZone(title: "Subir imagen") { model.load($0) }
                        .frame(maxWidth: 560, maxHeight: 320)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.bottom, 12)

            if let error = model.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger).padding(.bottom, 6)
            }

            if model.input != nil {
                bar
            }
        }
        .onAppear(perform: takeHandoff)
        .onChange(of: state.handoff) { takeHandoff() }
        .onChange(of: runner.results.count) { showResult = true }
        .onChange(of: model.safety) { model.safety = SafetyTolerance.clamp(model.safety, for: .outpaint) }
    }

    private var bar: some View {
        ToolBarContainer {
            TextField("Qué debe aparecer en la zona nueva (opcional)", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...3)
                .padding(.horizontal, 6)

            HStack(spacing: 8) {
                ChipPicker(icon: "aspectratio", title: "Proporción del lienzo", options: OutpaintModel.presets,
                           selection: $model.preset, label: { $0.label })
                ChipPicker(icon: "arrow.up.left.and.arrow.down.right", title: "Ampliar", options: OutpaintModel.expansions,
                           selection: $model.expand, label: { $0 == 1 ? "Ajustado" : "×\($0.formatted(.number.precision(.fractionLength(0...2))))" })
                sizeField("An", value: Int(model.canvasSize.width)) { model.setCanvas(width: $0) }
                Text("×").foregroundStyle(Theme.textSecondary)
                sizeField("Al", value: Int(model.canvasSize.height)) { model.setCanvas(height: $0) }
                Button { model.offset = nil } label: { Chip(icon: "scope", text: "Centrar") }
                    .buttonStyle(.plain)
                    .disabled(model.offset == nil)
                ChipPicker(icon: "speedometer", title: "Modo", options: OutpaintRequest.Mode.allCases,
                           selection: $model.mode, label: { $0 == .high ? "Alta calidad" : "Rápido" })
                ToolSettingsChip(model: model, showsSeed: false) {
                    Toggle("Recortar automáticamente (auto_crop)", isOn: $model.autoCrop)
                        .toggleStyle(.switch).controlSize(.small)
                    Toggle("Desactivar mejora automática del prompt", isOn: $model.disablePup)
                        .toggleStyle(.switch).controlSize(.small)
                }
                Spacer(minLength: 4)
                ToolGenerateControls(runner: runner, enabled: model.canGenerate) { model.generate(state: state) }
            }
        }
    }

    private func sizeField(_ label: String, value: Int, onCommit: @escaping (Int) -> Void) -> some View {
        SizeField(label: label, value: value, onCommit: onCommit)
    }

    private func takeHandoff() {
        guard let handoff = state.handoff, handoff.mode == .outpaint else { return }
        model.load(handoff.fileURL)
        state.handoff = nil
    }
}

/// Campo numérico de píxeles que se aplica al pulsar ↩ o salir del campo.
private struct SizeField: View {
    let label: String
    let value: Int
    let onCommit: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 46)
                .focused($focused)
                .onSubmit(commit)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.7)))
        .overlay(Capsule().strokeBorder(Theme.border))
        .onAppear { text = String(value) }
        .onChange(of: value) { if !focused { text = String(value) } }
        .onChange(of: focused) { if !focused { commit() } }
        .help("Píxeles (se envía la imagen reducida a 2560 px como máximo)")
    }

    private func commit() {
        if let v = Int(text.trimmingCharacters(in: .whitespaces)) { onCommit(v) }
        text = String(value)
    }
}

/// Lienzo con la imagen colocada dentro; arrastrarla fija reference_offset_x/y.
private struct OutpaintCanvas: View {
    @ObservedObject var model: OutpaintModel
    let input: ToolImage
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let canvas = model.canvasSize
            let scale = min((geo.size.width - 20) / canvas.width, (geo.size.height - 40) / canvas.height)
            let cw = canvas.width * scale, ch = canvas.height * scale
            let origin = CGPoint(x: (geo.size.width - cw) / 2, y: (geo.size.height - ch - 20) / 2)
            let offset = model.effectiveOffset

            ZStack(alignment: .topLeading) {
                // Lienzo
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.region, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .frame(width: cw, height: ch)
                    .offset(x: origin.x, y: origin.y)

                // Imagen arrastrable
                Image(nsImage: input.image)
                    .resizable()
                    .frame(width: input.size.width * scale, height: input.size.height * scale)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .offset(x: origin.x + offset.x * scale, y: origin.y + offset.y * scale)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                if dragStart == nil { dragStart = model.effectiveOffset }
                                guard let start = dragStart else { return }
                                let proposed = CGPoint(x: start.x + v.translation.width / scale,
                                                       y: start.y + v.translation.height / scale)
                                model.offset = OutpaintGeometry.clamp(proposed, source: input.size, canvas: canvas)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .help("Arrastra la imagen para colocarla dentro del lienzo")

                Text("Lienzo \(Int(canvas.width)) × \(Int(canvas.height)) px · imagen \(Int(input.size.width)) × \(Int(input.size.height)) px"
                     + (model.offset == nil ? " · centrada" : " · posición \(Int(offset.x)), \(Int(offset.y))"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: geo.size.width)
                    .offset(y: origin.y + ch + 8)
            }
        }
    }
}
