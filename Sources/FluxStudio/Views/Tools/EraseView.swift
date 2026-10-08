import FluxCore
import SwiftUI

/// Borrar: se pinta la máscara con un pincel sobre la imagen.
struct EraseView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: EraseModel
    @ObservedObject private var runner: ToolRunner
    @State private var showResult = true

    init(model: EraseModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolHeader(title: "Borrar", subtitle: "Pinta lo que quieres eliminar; el modelo rellena el hueco.") {
                if model.input != nil {
                    if runner.current != nil {
                        Picker("", selection: $showResult) {
                            Text("Máscara").tag(false)
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
                        ToolResultView(runner: runner, before: input.image) {
                            model.useCurrentResultAsInput()
                            showResult = false
                        }
                    } else {
                        MaskCanvas(model: model, input: input)
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
    }

    private var bar: some View {
        ToolBarContainer {
            HStack(spacing: 8) {
                Picker("", selection: $model.isEraser) {
                    Label("Pincel", systemImage: "paintbrush.pointed").tag(false)
                    Label("Goma", systemImage: "eraser").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)

                HStack(spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 6))
                    Slider(value: $model.brushRadius, in: 0.005...0.12)
                        .frame(width: 110)
                    Image(systemName: "circle.fill").font(.system(size: 13))
                }
                .foregroundStyle(Theme.textSecondary)
                .help("Tamaño del pincel")

                iconButton("arrow.uturn.backward", "Deshacer (⌘Z)", disabled: model.strokes.isEmpty) { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                iconButton("arrow.uturn.forward", "Rehacer (⇧⌘Z)", disabled: model.redoStack.isEmpty) { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Button { model.inverted.toggle() } label: {
                    Chip(icon: "circle.lefthalf.filled", text: "Invertir", isActive: model.inverted)
                }
                .buttonStyle(.plain)
                Button { model.clearMask() } label: { Chip(icon: "trash", text: "Limpiar") }
                    .buttonStyle(.plain)
                    .disabled(model.strokes.isEmpty && !model.inverted)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    SectionLabel("Ampliar máscara")
                    Slider(value: $model.dilatePixels, in: 0...25, step: 1).frame(width: 120)
                    Text("\(Int(model.dilatePixels)) px")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 40, alignment: .leading)
                }
                .help("dilate_pixels: agranda un poco la zona pintada para que el borde quede limpio (por defecto 10)")
                if model.maskIsEmpty {
                    Text("Pinta sobre lo que quieres borrar.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                ToolSettingsChip(model: model)
                ToolGenerateControls(runner: runner, enabled: !model.maskIsEmpty) { model.generate(state: state) }
            }
        }
    }

    private func iconButton(_ icon: String, _ help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 30, height: 28)
                .background(Capsule().fill(Color.white.opacity(0.7)))
                .overlay(Capsule().strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
    }

    private func takeHandoff() {
        guard let handoff = state.handoff, handoff.mode == .erase else { return }
        model.load(handoff.fileURL)
        state.handoff = nil
    }
}

/// Imagen con la máscara pintada encima (semitransparente).
private struct MaskCanvas: View {
    @ObservedObject var model: EraseModel
    let input: ToolImage
    @State private var current: MaskStroke?
    @State private var hover: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let size = fittedSize(input.size, in: geo.size)
            let frame = CGRect(x: (geo.size.width - size.width) / 2, y: (geo.size.height - size.height) / 2,
                               width: size.width, height: size.height)
            ZStack(alignment: .topLeading) {
                Image(nsImage: input.image)
                    .resizable()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)

                Canvas { ctx, canvasSize in
                    drawMask(in: &ctx, size: canvasSize)
                }
                .frame(width: frame.width, height: frame.height)
                .opacity(0.55)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)

                if let hover {
                    let r = model.brushRadius * frame.width
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 1.5)
                        .background(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 3))
                        .frame(width: r * 2, height: r * 2)
                        .offset(x: hover.x - r, y: hover.y - r)
                        .allowsHitTesting(false)
                }

                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .contentShape(Rectangle())
                    .offset(x: frame.minX, y: frame.minY)
                    .gesture(paintGesture(frame: frame))
                    .onContinuousHover(coordinateSpace: .named("mask")) { phase in
                        switch phase {
                        case .active(let p): hover = p
                        case .ended: hover = nil
                        }
                    }
            }
            .coordinateSpace(name: "mask")
        }
    }

    private func normalized(_ p: CGPoint, frame: CGRect) -> CGPoint {
        CGPoint(x: min(max((p.x - frame.minX) / frame.width, 0), 1),
                y: min(max((p.y - frame.minY) / frame.height, 0), 1))
    }

    private func paintGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("mask"))
            .onChanged { value in
                hover = value.location
                let point = normalized(value.location, frame: frame)
                if current == nil {
                    current = MaskStroke(points: [point], radius: model.brushRadius, erases: model.isEraser)
                } else {
                    current?.points.append(point)
                }
            }
            .onEnded { _ in
                if let stroke = current { model.add(stroke) }
                current = nil
            }
    }

    /// Misma lógica que MaskRenderer, pero en pantalla y en violeta.
    private func drawMask(in ctx: inout GraphicsContext, size: CGSize) {
        let color = Theme.region
        let all = model.strokes + (current.map { [$0] } ?? [])
        ctx.drawLayer { layer in
            if model.inverted {
                layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            }
            for stroke in all where !stroke.points.isEmpty {
                let paints = stroke.erases == model.inverted
                layer.blendMode = paints ? .normal : .clear
                let r = stroke.radius * size.width
                let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                if pts.count == 1 {
                    layer.fill(Path(ellipseIn: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: r * 2, height: r * 2)),
                               with: .color(color))
                } else {
                    var path = Path()
                    path.addLines(pts)
                    layer.stroke(path, with: .color(color),
                                 style: StrokeStyle(lineWidth: r * 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
