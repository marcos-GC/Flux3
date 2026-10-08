import AppKit
import FluxCore
import SwiftUI

/// Barra inferior de Vídeo: modo, fotogramas clave, prompt y opciones.
struct VideoBar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    @ObservedObject var model: VideoModel
    @ObservedObject private var runner: ToolRunner
    @State private var showSettings = false

    init(model: VideoModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    private var focusedIsVideo: Bool { VideoModel.isVideo(state.focusedURL) }
    private var focusedIsImage: Bool { state.focusedURL != nil && !focusedIsVideo }
    private var focusedRecord: StoredResult? { history.items.first { $0.fileURL == state.focusedURL } }

    var body: some View {
        ToolBarContainer {
            modePicker

            if let draft = focusedRecord, draft.record.draftCaches?.isEmpty == false {
                draftBanner(draft)
            }

            if model.mode == .i2v {
                keyframeStrip
            }
            if model.mode.needsVideo && !focusedIsVideo {
                Label("Selecciona un vídeo en la tira de la derecha.", systemImage: "film")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
            }

            TextField(promptPlaceholder, text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(.horizontal, 6)

            HStack(spacing: 8) {
                switch model.mode {
                case .t2v, .i2v, .v2v:
                    ChipPicker(icon: "clock", title: "Duración", options: [0] + Array(Flux3Video.durations),
                               selection: Binding(get: { model.duration ?? 0 }, set: { model.duration = $0 == 0 ? nil : $0 }),
                               label: { $0 == 0 ? "Auto" : "\($0) s" })
                    ChipPicker(icon: "viewfinder", title: "Resolución", options: Flux3Video.resolutions,
                               selection: $model.resolution, label: { Flux3Video.resolutionLabel($0) })
                        .disabled(model.draft)
                    ChipPicker(icon: "aspectratio", title: "Proporción", options: Flux3Video.aspectRatios,
                               selection: $model.aspectRatio, label: { $0 == "auto" ? "Auto" : $0 })
                    toggleChip(model.generateAudio ? "speaker.wave.2" : "speaker.slash",
                               model.generateAudio ? "Con audio" : "Sin audio", isOn: $model.generateAudio)
                    toggleChip("hare", "Borrador rápido", isOn: $model.draft)
                        .help("Vista previa rápida y barata en HD. Si te gusta, «Renderizar a calidad final».")
                case .upscale:
                    ChipPicker(icon: "arrow.up.left.and.arrow.down.right", title: "Factor", options: [1.5, 2.0, 2.5, 3.0],
                               selection: $model.upscaleFactor, label: { "×\($0.formatted(.number.precision(.fractionLength(0...1))))" })
                    ChipPicker(icon: "sparkle", title: "Creatividad", options: [0, 1],
                               selection: $model.creativity, label: { $0 == 0 ? "Fiel al original" : "Añadir detalle" })
                        .help("«Añadir detalle» inventa textura: mejor en vídeos generados; puede alterar caras y textos y cuesta ~40 % más.")
                case .edit:
                    Text("Describe qué cambia dentro del clip (máx. 15 s); el resto se mantiene.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                Button { showSettings.toggle() } label: {
                    Chip(icon: "slider.horizontal.3", text: "Ajustes", isActive: showSettings)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                    SafetyToleranceControl(value: $model.safety, range: SafetyTolerance.range(for: .flux3Video))
                        .padding(16)
                        .frame(width: 320)
                }

                Spacer(minLength: 4)
                ToolGenerateControls(runner: runner, enabled: canGenerate) {
                    model.generate(state: state, focused: state.focusedURL)
                }
            }
        }
    }

    private var canGenerate: Bool {
        switch model.mode {
        case .t2v: return !model.prompt.trimmingCharacters(in: .whitespaces).isEmpty
        case .i2v: return !model.keyframes.isEmpty && !model.keyframes.contains(where: \.isProcessing)
        case .v2v, .upscale: return focusedIsVideo
        case .edit: return focusedIsVideo && !model.prompt.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var promptPlaceholder: String {
        switch model.mode {
        case .t2v: return "Describe el vídeo: qué pasa, movimiento de cámara, luz, sonido…"
        case .i2v: return "Qué se mueve y cómo cambia entre los fotogramas (no repitas lo que ya se ve)"
        case .v2v: return "Qué pasa a continuación (desde el final del vídeo seleccionado)"
        case .edit: return "Qué debe cambiar dentro del vídeo (p. ej. «convierte el día en atardecer»)"
        case .upscale: return "Qué muestra el vídeo (opcional, orienta el detalle)"
        }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(VideoModel.Mode.allCases) { mode in
                Button { model.mode = mode } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon).font(.system(size: 11))
                        Text(mode.title).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(model.mode == mode ? Color.white : Theme.textPrimary)
                    .background(Capsule().fill(model.mode == mode ? Theme.action : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Theme.border))
    }

    private func toggleChip(_ icon: String, _ title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Chip(icon: icon, text: title, isActive: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
    }

    private func draftBanner(_ item: StoredResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hare").foregroundStyle(Theme.region)
            Text("Este vídeo es un borrador.").font(.system(size: 12, weight: .medium))
            ChipPicker(icon: "viewfinder", title: "Resolución final", options: Flux3Video.resolutions,
                       selection: $model.finalResolution, label: { Flux3Video.resolutionLabel($0) })
            Button { model.renderFinal(state: state, item: item) } label: {
                Chip(icon: "sparkles", text: "Renderizar a calidad final", isActive: true)
            }
            .buttonStyle(.plain)
            .disabled(runner.isRunning)
            Spacer()
            Text("La caché del borrador caduca en ~1 hora.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.region.opacity(0.08)))
    }

    // MARK: Fotogramas clave

    private var keyframeStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(model.keyframes.enumerated()), id: \.element.id) { index, frame in
                            keyframeThumb(frame, index: index)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        if let url = state.focusedURL { model.addKeyframes([url]) }
                    } label: { Chip(icon: "plus", text: "Imagen seleccionada") }
                        .buttonStyle(.plain)
                        .disabled(!focusedIsImage || model.keyframes.count >= Flux3Video.maxKeyframes)
                    Button { model.addKeyframes(chooseImages()) } label: { Chip(icon: "folder", text: "Desde archivo") }
                        .buttonStyle(.plain)
                        .disabled(model.keyframes.count >= Flux3Video.maxKeyframes)
                }
            }
            HStack(spacing: 8) {
                Toggle("Fijar el segundo de cada fotograma", isOn: $model.useTimestamps)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                Text(keyframeHint)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.useTimestamps && !model.keyframes.isEmpty {
                timeline
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addKeyframes(urls)
            return true
        }
    }

    private var keyframeHint: String {
        switch model.keyframes.count {
        case 0: return "Añade de 1 a 10 imágenes (también puedes arrastrarlas aquí)."
        case 1: return "1 imagen = fotograma inicial."
        case 2: return "2 imágenes = inicio y final."
        default: return "3 o más = storyboard\(model.useTimestamps || model.duration != nil ? "" : " (elige una duración)")."
        }
    }

    private func keyframeThumb(_ frame: VideoKeyframe, index: Int) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Theme.placeholder)
                if let thumb = frame.thumbnail { Image(nsImage: thumb).resizable().scaledToFill() }
                if frame.isProcessing { ProgressView().controlSize(.mini) }
                if frame.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.black.opacity(0.65)))
                    .padding(3)
            }
            .help(frame.error ?? frame.url.lastPathComponent)
            .contextMenu {
                Button("Mover a la izquierda") { model.moveKeyframe(frame.id, by: -1) }.disabled(index == 0)
                Button("Mover a la derecha") { model.moveKeyframe(frame.id, by: 1) }.disabled(index == model.keyframes.count - 1)
                Divider()
                Button("Quitar") { model.removeKeyframe(frame.id) }
            }
            HStack(spacing: 2) {
                smallButton("chevron.left") { model.moveKeyframe(frame.id, by: -1) }.disabled(index == 0)
                smallButton("xmark") { model.removeKeyframe(frame.id) }
                smallButton("chevron.right") { model.moveKeyframe(frame.id, by: 1) }.disabled(index == model.keyframes.count - 1)
            }
            if model.useTimestamps {
                TextField("s", value: Binding(
                    get: { frame.seconds },
                    set: { v in if let i = model.keyframes.firstIndex(where: { $0.id == frame.id }) { model.keyframes[i].seconds = max(0, min(20, v)) } }
                ), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 50)
                .help("Segundo en el que aparece este fotograma")
            }
        }
    }

    private func smallButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold)).frame(width: 16, height: 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textSecondary)
    }

    /// Línea de tiempo con un marcador por fotograma.
    private var timeline: some View {
        let total = Double(model.duration ?? max(5, Int((model.keyframes.map(\.seconds).max() ?? 5).rounded(.up))))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border).frame(height: 4)
                ForEach(Array(model.keyframes.enumerated()), id: \.element.id) { index, frame in
                    let x = CGFloat(min(frame.seconds, total) / max(total, 1)) * (geo.size.width - 14)
                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Theme.region))
                        .offset(x: x)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
        .overlay(alignment: .trailing) {
            Text("\(Int(total)) s").font(.system(size: 9)).foregroundStyle(Theme.textSecondary).offset(y: 12)
        }
    }
}
