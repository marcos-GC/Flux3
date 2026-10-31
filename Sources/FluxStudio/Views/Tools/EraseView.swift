import FluxCore
import SwiftUI

/// Barra inferior de Borrar: marcar, desmarcar, deshacer, invertir…
struct EraseBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: EraseModel
    @ObservedObject private var runner: ToolRunner

    init(model: EraseModel) {
        self.model = model
        self._runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        ToolBarContainer {
            MaskBrushControls(model: model, paintHelp: "lo que quieres borrar")

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
                    Text(model.isEraser
                         ? "«Desmarcar» solo quita pintura violeta. Usa «Marcar» para señalar lo que quieres borrar."
                         : "Pinta en violeta lo que quieres borrar y pulsa ↑.")
                        .font(.system(size: 12))
                        .foregroundStyle(model.isEraser ? Theme.danger : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                ToolSettingsChip(model: model)
                ToolGenerateControls(runner: runner, enabled: !model.maskIsEmpty) { model.generate(state: state) }
            }
        }
    }
}

/// Imagen con la máscara en el escenario (Borrar y Pintar y rellenar).
struct MaskStage: View {
    @ObservedObject var model: MaskToolModel

    var body: some View {
        if let input = model.input {
            MaskCanvas(model: model, input: input)
        } else {
            ToolLoadingView(isLoading: model.isLoading, error: model.loadError)
        }
    }
}

/// Imagen con la máscara pintada encima (semitransparente).
private struct MaskCanvas: View {
    @ObservedObject var model: MaskToolModel
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

                polygonOverlay(frame: frame)

                if let hover, model.shape == .brush {
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
                    .gesture(activeGesture(frame: frame))
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

    @ViewBuilder
    private func polygonOverlay(frame: CGRect) -> some View {
        if model.shape == .polygon {
            let points: [CGPoint] = model.pendingPolygon.map { denormalized($0, frame: frame) }
            PolygonOverlay(points: points, hover: hover, closeRadius: Self.closeRadius)
                .allowsHitTesting(false)
        }
    }

    private func activeGesture(frame: CGRect) -> AnyGesture<DragGesture.Value> {
        if model.shape == .polygon {
            return AnyGesture(polygonGesture(frame: frame))
        }
        return AnyGesture(paintGesture(frame: frame))
    }

    /// Distancia (en puntos de pantalla) a la que un clic sobre el primer vértice cierra el polígono.
    static let closeRadius: CGFloat = 9

    private func denormalized(_ p: CGPoint, frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + p.x * frame.width, y: frame.minY + p.y * frame.height)
    }

    /// Polígono: cada clic añade un vértice; un clic sobre el primero lo cierra.
    private func polygonGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("mask"))
            .onEnded { value in
                hover = value.location
                if model.canClosePolygon, let first = model.pendingPolygon.first {
                    let p = denormalized(first, frame: frame)
                    let dx: CGFloat = p.x - value.location.x
                    let dy: CGFloat = p.y - value.location.y
                    if (dx * dx + dy * dy).squareRoot() <= Self.closeRadius {
                        model.closePolygon()
                        return
                    }
                }
                model.addPolygonPoint(normalized(value.location, frame: frame))
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
                    // Sin nada marcado no hay nada que desmarcar: se pinta directamente.
                    if model.isEraser && model.maskIsEmpty { model.isEraser = false }
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
            for stroke in all where stroke.hasArea {
                let paints = stroke.erases == model.inverted
                layer.blendMode = paints ? .normal : .clear
                let r = stroke.radius * size.width
                let pts = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                if stroke.isPolygon {
                    var path = Path()
                    path.addLines(pts)
                    path.closeSubpath()
                    layer.fill(path, with: .color(color))
                } else if pts.count == 1 {
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

/// Controles del pincel: marcar o desmarcar, tamaño, deshacer, rehacer, invertir y limpiar.
struct MaskBrushControls: View {
    @ObservedObject var model: MaskToolModel
    /// Qué se marca, para las ayudas («lo que quieres borrar», «la zona que quieres cambiar»…).
    let paintHelp: String

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.shape) {
                Image(systemName: "paintbrush").tag(MaskToolModel.Shape.brush)
                Image(systemName: "pentagon").tag(MaskToolModel.Shape.polygon)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 76)
            .help("Pincel: pinta a mano alzada · Polígono: clic a clic con líneas rectas para formas exactas (una mesa, una pared…); clic en el primer punto para cerrar")

            // «Marcar» pinta en violeta; «Desmarcar» solo corrige esa pintura.
            Picker("", selection: $model.isEraser) {
                Label("Marcar", systemImage: "paintbrush.pointed").tag(false)
                Label("Desmarcar", systemImage: "minus.circle").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 200)
            .help("Marcar: pinta en violeta \(paintHelp) · Desmarcar: quita pintura violeta si te has pasado")

            if model.shape == .brush {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill").font(.system(size: 6))
                    Slider(value: $model.brushRadius, in: 0.005...0.12)
                        .frame(width: 110)
                    Image(systemName: "circle.fill").font(.system(size: 13))
                }
                .foregroundStyle(Theme.textSecondary)
                .help("Tamaño del pincel")
            } else if model.pendingPolygon.isEmpty {
                Text("Haz clic en cada esquina")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Button { model.closePolygon() } label: { Chip(icon: "checkmark", text: "Cerrar forma") }
                    .buttonStyle(.plain)
                    .disabled(!model.canClosePolygon)
                    .help("Cierra el polígono (también: clic en el primer punto)")
                Button { model.cancelPolygon() } label: { Chip(icon: "xmark", text: "Cancelar") }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .help("Descarta la forma a medias (Esc)")
            }

            iconButton("arrow.uturn.backward", "Deshacer (⌘Z)", disabled: model.strokes.isEmpty && model.pendingPolygon.isEmpty) { model.undo() }
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
}

/// Polígono a medias: líneas entre vértices, línea hasta el ratón y el primer punto destacado.
private struct PolygonOverlay: View {
    let points: [CGPoint]
    let hover: CGPoint?
    let closeRadius: CGFloat

    private func isNear(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let dx: CGFloat = a.x - b.x
        let dy: CGFloat = a.y - b.y
        return (dx * dx + dy * dy).squareRoot() <= closeRadius
    }

    var body: some View {
        Canvas { ctx, _ in
            guard let first = points.first else { return }
            var path = Path()
            path.addLines(points)
            if let hover { path.addLine(to: hover) }
            ctx.stroke(path, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            for (i, p) in points.enumerated() {
                let r: CGFloat = i == 0 ? closeRadius * 0.7 : 3.5
                let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                ctx.fill(dot, with: .color(i == 0 ? Theme.region : .white))
                ctx.stroke(dot, with: .color(.black.opacity(0.5)), lineWidth: 1)
            }
            // Si el ratón está sobre el primer punto, se indica que el clic cierra la forma.
            if points.count >= 3, let hover, isNear(hover, first) {
                let ring = Path(ellipseIn: CGRect(x: first.x - closeRadius, y: first.y - closeRadius,
                                                  width: closeRadius * 2, height: closeRadius * 2))
                ctx.stroke(ring, with: .color(.white), lineWidth: 2)
            }
        }
    }
}
