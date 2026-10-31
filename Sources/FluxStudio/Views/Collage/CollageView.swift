import AppKit
import FluxCore
import QuartzCore
import SwiftUI

/// Herramienta Collage: foto base + capas que se transforman como en Photoshop,
/// y «Hacer realista» con FLUX 3 Image.
struct CollageWorkspace: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: CollageModel
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            if model.base == nil {
                CollageEmptyState(model: model)
            } else {
                CollageCanvas(model: model)
                HStack {
                    Spacer()
                    CollageLayersPanel(model: model)
                        .frame(width: 240)
                        .padding(.top, 24)
                        .padding(.trailing, 16)
                        .padding(.bottom, 250)
                }
                VStack(spacing: 8) {
                    Spacer()
                    CollageToolbar(model: model)
                    CollageBar(model: model)
                        .padding(.bottom, 20)
                }
            }
        }
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
    }

    // MARK: Teclado

    private func installMonitor() {
        guard monitor == nil else { return }
        let model = self.model
        let state = self.state
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed: Bool = MainActor.assumeIsolated { Self.handle(event, model: model, state: state) }
            return consumed ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    @MainActor
    private static func handle(_ event: NSEvent, model: CollageModel, state: AppState) -> Bool {
        guard state.tool == .collage, state.mode == .generate, state.compareURL == nil,
              NSApp.keyWindow?.attachedSheet == nil,
              !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command, key == "z" { model.undo(); return true }
        if flags == [.command, .shift], key == "z" { model.redo(); return true }
        guard let id = model.selectedID else { return false }
        if flags == .command, key == "d" { model.duplicate(id); return true }
        if flags.isEmpty {
            switch key {
            case "e": model.brushMode = model.brushMode == .erase ? nil : .erase; return true
            case "r": model.brushMode = model.brushMode == .restore ? nil : .restore; return true
            case "v": model.brushMode = nil; return true
            case "[": model.brushSize = max(4, model.brushSize / 1.25); return true
            case "]": model.brushSize = min(400, model.brushSize * 1.25); return true
            default: break
            }
        }
        switch event.keyCode {
        case 51, 117: // ⌫ / Supr
            model.remove(id)
            return true
        case 53: // Esc: primero deja la goma; si no, quita la selección.
            if model.brushMode != nil { model.brushMode = nil } else { model.selectedID = nil }
            return true
        case 123, 124, 125, 126: // flechas: mover un poco (⇧ = más)
            let step: CGFloat = (flags.contains(.shift) ? 10 : 1) * max(1, model.canvasSize.width / 1000)
            let d: CGVector
            switch event.keyCode {
            case 123: d = CGVector(dx: -step, dy: 0)
            case 124: d = CGVector(dx: step, dy: 0)
            case 125: d = CGVector(dx: 0, dy: step)
            default: d = CGVector(dx: 0, dy: -step)
            }
            model.edit(id) { $0.quad = $0.quad.translated(by: d) }
            return true
        default:
            return false
        }
    }
}

// MARK: - Lienzo

/// Dónde se pinta el lienzo y cómo se pasa de pantalla a píxeles del collage.
struct CollageLayout {
    let scale: CGFloat
    let frame: CGRect

    init(container: CGSize, canvas: CGSize) {
        let insets = EdgeInsets(top: 28, leading: 32, bottom: 250, trailing: 280)
        let availW = max(100, container.width - insets.leading - insets.trailing)
        let availH = max(100, container.height - insets.top - insets.bottom)
        scale = min(availW / max(canvas.width, 1), availH / max(canvas.height, 1))
        let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        frame = CGRect(x: insets.leading + (availW - size.width) / 2, y: insets.top + (availH - size.height) / 2,
                       width: size.width, height: size.height)
    }

    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: frame.minX + p.x * scale, y: frame.minY + p.y * scale) }
    func toCanvas(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - frame.minX) / scale, y: (p.y - frame.minY) / scale) }
    func viewQuad(_ q: CollageQuad) -> CollageQuad { CollageQuad(corners: q.corners.map(toView)) }
}

/// Qué se está arrastrando.
private enum CollageHandle: Equatable {
    case move, corner(Int), edge(Int), rotate
}

private struct CollageDrag {
    let layerID: UUID
    let handle: CollageHandle
    let startQuad: CollageQuad
    let startPoint: CGPoint
    var didChange = false
}

private struct CollageCanvas: View {
    @ObservedObject var model: CollageModel
    @State private var drag: CollageDrag?
    @State private var pressedNothing = false
    @State private var painting = false
    @State private var hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let layout = CollageLayout(container: geo.size, canvas: model.canvasSize)
            ZStack(alignment: .topLeading) {
                Theme.background

                if let base = model.base {
                    Image(nsImage: base.image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: layout.frame.width, height: layout.frame.height)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .offset(x: layout.frame.minX, y: layout.frame.minY)
                }

                // Capas (lo que sale del lienzo no cuenta: se recorta igual que al aplanar).
                ZStack(alignment: .topLeading) {
                    ForEach(model.layers) { layer in
                        if layer.isVisible {
                            CollageLayerImage(layer: layer, quad: layout.viewQuad(layer.quad))
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: layout.frame.width, height: layout.frame.height)
                        .offset(x: layout.frame.minX, y: layout.frame.minY)
                }

                if let layer = model.selected, layer.isVisible {
                    if model.brushMode != nil {
                        // Con la goma, solo el contorno de la capa (sin tiradores).
                        Path { path in
                            let q = layout.viewQuad(layer.quad)
                            path.move(to: q.corners[0])
                            for i in 1..<4 { path.addLine(to: q.corners[i]) }
                            path.closeSubpath()
                        }
                        .stroke(Theme.region.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .allowsHitTesting(false)
                    } else {
                        CollageSelection(quad: layout.viewQuad(layer.quad), busy: model.cuttingOut.contains(layer.id))
                    }
                }

                // Cursor del pincel.
                if model.brushMode != nil, model.selected != nil, let p = hoverPoint {
                    Circle()
                        .strokeBorder(model.brushMode == .erase ? Color.white : Theme.region, lineWidth: 1.5)
                        .background(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5).padding(-1))
                        .frame(width: model.brushSize, height: model.brushSize)
                        .offset(x: p.x - model.brushSize / 2, y: p.y - model.brushSize / 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(layout))
            .coordinateSpace(name: "collage")
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hoverPoint = p
                case .ended: hoverPoint = nil
                }
            }
        }
    }

    // MARK: Gestos

    private func dragGesture(_ layout: CollageLayout) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("collage"))
            .onChanged { value in
                hoverPoint = value.location
                // Goma / recuperar: se pinta sobre la capa seleccionada.
                if model.brushMode != nil, let layer = model.selected {
                    if !painting {
                        painting = true
                        model.beginStroke()
                    }
                    paint(at: value.location, layer: layer, layout: layout)
                    return
                }
                if drag == nil && !pressedNothing { begin(at: value.startLocation, layout: layout) }
                guard var current = drag else { return }
                let moved = value.translation.width != 0 || value.translation.height != 0
                guard moved else { return }
                if !current.didChange {
                    model.pushUndo()
                    current.didChange = true
                    drag = current
                }
                apply(current, location: value.location, layout: layout)
            }
            .onEnded { _ in
                if painting {
                    painting = false
                    model.endStroke()
                    return
                }
                if pressedNothing { model.selectedID = nil }
                drag = nil
                pressedNothing = false
            }
    }

    /// Lleva un punto de pantalla a píxeles de la imagen de la capa (aunque esté girada o en perspectiva).
    private func paint(at location: CGPoint, layer: CollageLayer, layout: CollageLayout) {
        guard let uv = layer.quad.homography.invert(layout.toCanvas(location)) else { return }
        let w = CGFloat(layer.original.width), h = CGFloat(layer.original.height)
        let imagePoint = CGPoint(x: uv.x * w, y: uv.y * h)
        // Píxeles de pantalla por píxel de imagen (aproximado si hay perspectiva).
        let screenPerPixel = layout.scale * layer.quad.approximateSize.width / max(w, 1)
        let radius = model.brushSize / 2 / max(screenPerPixel, 0.0001)
        model.continueStroke(to: imagePoint, radius: radius)
    }

    private func begin(at point: CGPoint, layout: CollageLayout) {
        // 1) Tiradores de la capa seleccionada.
        if let layer = model.selected, layer.isVisible,
           let handle = CollageSelection.handle(at: point, quad: layout.viewQuad(layer.quad)) {
            drag = CollageDrag(layerID: layer.id, handle: handle, startQuad: layer.quad, startPoint: point)
            return
        }
        // 2) La capa más alta bajo el puntero: se selecciona y se mueve.
        if let layer = model.layer(at: layout.toCanvas(point)) {
            model.selectedID = layer.id
            drag = CollageDrag(layerID: layer.id, handle: .move, startQuad: layer.quad, startPoint: point)
            return
        }
        // 3) Nada: al soltar se quita la selección.
        pressedNothing = true
    }

    private func apply(_ d: CollageDrag, location: CGPoint, layout: CollageLayout) {
        let flags = NSEvent.modifierFlags
        let delta = CGVector(dx: (location.x - d.startPoint.x) / layout.scale,
                             dy: (location.y - d.startPoint.y) / layout.scale)
        let pointer = layout.toCanvas(location)
        let quad: CollageQuad
        switch d.handle {
        case .move:
            var m = delta
            // ⇧: solo en horizontal o en vertical.
            if flags.contains(.shift) {
                if abs(m.dx) > abs(m.dy) { m.dy = 0 } else { m.dx = 0 }
            }
            quad = d.startQuad.translated(by: m)
        case .corner(let i):
            if flags.contains(.command) {
                // ⌘: perspectiva / distorsión, mueve solo esa esquina.
                quad = d.startQuad.movingCorner(i, to: d.startQuad.corners[i] + delta)
            } else {
                quad = d.startQuad.scaledFromCorner(i, to: pointer)
            }
        case .edge(let e):
            quad = d.startQuad.stretchedEdge(e, by: delta)
        case .rotate:
            let c = d.startQuad.center
            let start = layout.toCanvas(d.startPoint)
            var angle = atan2(pointer.y - c.y, pointer.x - c.x) - atan2(start.y - c.y, start.x - c.x)
            // ⇧: de 15 en 15 grados.
            if flags.contains(.shift) {
                let step = CGFloat.pi / 12
                angle = (angle / step).rounded() * step
            }
            quad = d.startQuad.rotated(by: angle, around: c)
        }
        model.update(d.layerID) { $0.quad = quad }
    }
}

/// Una capa pintada en su cuadrilátero con una transformación proyectiva (como Photoshop).
private struct CollageLayerImage: View {
    let layer: CollageLayer
    /// Cuadrilátero en coordenadas de pantalla.
    let quad: CollageQuad

    var body: some View {
        let size = quad.approximateSize
        let w = max(size.width, 1), h = max(size.height, 1)
        let hm = quad.homography
        var t = CATransform3DIdentity
        t.m11 = hm.a / w; t.m12 = hm.d / w; t.m14 = hm.g / w
        t.m21 = hm.b / h; t.m22 = hm.e / h; t.m24 = hm.h / h
        t.m41 = hm.c; t.m42 = hm.f; t.m44 = 1
        return Image(nsImage: layer.image)
            .resizable()
            .interpolation(.high)
            .frame(width: w, height: h)
            .opacity(layer.opacity)
            .projectionEffect(ProjectionTransform(t))
            .allowsHitTesting(false)
    }
}

/// Marco de transformación: esquinas, lados y tirador de giro.
private struct CollageSelection: View {
    let quad: CollageQuad
    var busy = false

    static let handleRadius: CGFloat = 9
    static let rotateDistance: CGFloat = 28

    static func rotatePoint(_ q: CollageQuad) -> CGPoint {
        let top = q.edgeMidpoint(0)
        let dir = top - q.center
        let len = max(dir.length, 1)
        return top + dir * (rotateDistance / len)
    }

    /// Tirador bajo el puntero (en coordenadas de pantalla), si lo hay.
    static func handle(at p: CGPoint, quad q: CollageQuad) -> CollageHandle? {
        let r = handleRadius + 3
        if p.distance(to: rotatePoint(q)) <= r { return .rotate }
        for i in 0..<4 where p.distance(to: q.corners[i]) <= r { return .corner(i) }
        for e in 0..<4 where p.distance(to: q.edgeMidpoint(e)) <= r { return .edge(e) }
        return nil
    }

    var body: some View {
        let rotate = Self.rotatePoint(quad)
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: quad.corners[0])
                for i in 1..<4 { path.addLine(to: quad.corners[i]) }
                path.closeSubpath()
                path.move(to: quad.edgeMidpoint(0))
                path.addLine(to: rotate)
            }
            .stroke(Theme.region, lineWidth: 1.5)

            ForEach(0..<4, id: \.self) { i in
                handle(at: quad.corners[i], size: 11, square: true)
                handle(at: quad.edgeMidpoint(i), size: 8, square: true)
            }
            Circle()
                .fill(Color.white)
                .overlay(Circle().strokeBorder(Theme.region, lineWidth: 1.5))
                .overlay(Image(systemName: "arrow.clockwise").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.region))
                .frame(width: 18, height: 18)
                .offset(x: rotate.x - 9, y: rotate.y - 9)

            if busy {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(Circle().fill(Color.white.opacity(0.9)))
                    .offset(x: quad.center.x - 16, y: quad.center.y - 16)
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(at p: CGPoint, size: CGFloat, square: Bool) -> some View {
        Rectangle()
            .fill(Color.white)
            .overlay(Rectangle().strokeBorder(Theme.region, lineWidth: 1.5))
            .frame(width: size, height: size)
            .offset(x: p.x - size / 2, y: p.y - size / 2)
    }
}

// MARK: - Panel de capas

private struct CollageLayersPanel: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: CollageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Capas")
                Spacer()
                Button { model.add(chooseImages()) } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Añadir objetos (PNG recortados o fotos)")
            }

            ScrollView {
                VStack(spacing: 4) {
                    // Arriba = delante.
                    ForEach(Array(model.layers.reversed())) { layer in
                        row(layer)
                    }
                    if model.layers.isEmpty {
                        Text("Añade objetos con + , arrastrándolos aquí o con ⌘V.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                    baseRow
                }
            }
            .frame(maxHeight: 260)

            if let layer = model.selected {
                Divider()
                selectedControls(layer)
            }
        }
        .padding(12)
        .surfaceStyle(cornerRadius: 14)
    }

    private func row(_ layer: CollageLayer) -> some View {
        let selected = model.selectedID == layer.id
        return HStack(spacing: 8) {
            thumb(layer.image)
            Text(layer.name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if model.cuttingOut.contains(layer.id) {
                ProgressView().controlSize(.mini)
            }
            Button { model.edit(layer.id) { $0.isVisible.toggle() } } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(layer.isVisible ? Theme.textPrimary : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help(layer.isVisible ? "Ocultar capa" : "Mostrar capa")
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Theme.region.opacity(0.14) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = layer.id }
    }

    private var baseRow: some View {
        HStack(spacing: 8) {
            if let base = model.base { thumb(base.image) }
            Text("Base").font(.system(size: 11, weight: .medium))
            Spacer()
            Menu {
                Button("Elegir otra foto…") {
                    if let url = chooseImages(allowsMultiple: false).first { model.setBase(url) }
                }
                if let url = state.focusedURL, !VideoModel.isVideo(url) {
                    Button("Usar la imagen seleccionada") { model.setBase(url) }
                }
                Divider()
                Button("Empezar un collage nuevo", role: .destructive) { model.reset() }
            } label: {
                Text("Cambiar").font(.system(size: 11))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.placeholder.opacity(0.5)))
    }

    private func thumb(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .background(
                // Cuadros para ver la transparencia.
                Image(systemName: "checkerboard.rectangle").resizable().opacity(0.08)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func selectedControls(_ layer: CollageLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            brushControls(layer)

            CutoutControls(model: model, layer: layer)
                .id(layer.id)

            HStack(spacing: 6) {
                Text("Opacidad").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                Slider(value: Binding(
                    get: { layer.opacity },
                    set: { value in model.update(layer.id) { $0.opacity = value } }
                ), in: 0.1...1, onEditingChanged: { editing in
                    if editing { model.pushUndo() }
                })
                .controlSize(.mini)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", "Voltear en horizontal") {
                    model.edit(layer.id) { $0.quad = $0.quad.flippedHorizontally }
                }
                iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", "Voltear en vertical") {
                    model.edit(layer.id) { $0.quad = $0.quad.flippedVertically }
                }
                iconButton("square.2.layers.3d.top.filled", "Traer hacia delante") { model.move(layer.id, by: 1) }
                iconButton("square.2.layers.3d.bottom.filled", "Enviar hacia atrás") { model.move(layer.id, by: -1) }
                iconButton("plus.square.on.square", "Duplicar (⌘D)") { model.duplicate(layer.id) }
                iconButton("arrow.counterclockwise", "Quitar giro, estiramiento y perspectiva") { model.resetTransform(layer.id) }
                iconButton("trash", "Borrar capa (⌫)", color: Theme.danger) { model.remove(layer.id) }
            }
        }
    }

    @ViewBuilder
    private func brushControls(_ layer: CollageLayer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Herramienta", selection: $model.brushMode) {
                Text("Mover").tag(CollageModel.BrushMode?.none)
                Text("Goma").tag(CollageModel.BrushMode?.some(.erase))
                Text("Recuperar").tag(CollageModel.BrushMode?.some(.restore))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Mover/transformar (V) · Goma: borra partes de la capa (E) · Recuperar: vuelve a pintar lo borrado (R)")

            if model.brushMode != nil {
                HStack(spacing: 6) {
                    Text("Tamaño").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Slider(value: $model.brushSize, in: 4...400)
                        .controlSize(.mini)
                    Text("\(Int(model.brushSize))").font(.system(size: 10)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, alignment: .trailing)
                }
                .help("Tamaño del pincel ([ y ] para cambiarlo)")
            }
            if layer.mask != nil {
                Button("Recuperar todo lo borrado") { model.clearMask(layer.id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.region)
            }
        }
    }

    private func iconButton(_ icon: String, _ help: String, color: Color = Theme.textPrimary,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Barras

private struct CollageToolbar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: CollageModel

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                Button("Renombrar…") { renameProject() }
                Button("Mostrar en Finder") { model.revealProjectInFinder() }
                Divider()
                Button("Nuevo collage") { model.reset() }
                if !model.recentProjects.isEmpty {
                    Menu("Abrir") {
                        ForEach(model.recentProjects) { project in
                            Button("\(project.name) · \(project.modified.formatted(date: .abbreviated, time: .shortened))") {
                                model.open(project, state: state)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.3.layers.3d").font(.system(size: 12))
                    Text(model.projectName.isEmpty ? "Collage sin guardar" : model.projectName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 180)
                }
                .padding(.horizontal, 8)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Se guarda solo en «Collages/Proyectos», dentro de la carpeta de salida. Desde aquí puedes renombrarlo, abrir otro o empezar uno nuevo.")
            divider
            ToolTextButton(icon: "photo.badge.plus", title: "Añadir objetos") { model.add(chooseImages()) }
            divider
            ToolTextButton(icon: "arrow.uturn.backward", title: "Deshacer") { model.undo() }
                .disabled(!model.canUndo)
                .help("Deshacer (⌘Z)")
            ToolTextButton(icon: "arrow.uturn.forward", title: "Rehacer") { model.redo() }
                .disabled(!model.canRedo)
                .help("Rehacer (⇧⌘Z)")
            divider
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .help("""
                Arrastra un objeto para moverlo (⇧ = recto).
                Esquinas: escalar sin deformar. ⌘ + esquina: perspectiva.
                Lados: más ancho, estrecho, alto o bajo.
                Círculo de arriba: girar (⇧ = de 15 en 15°).
                Flechas: mover un poco · ⌘D duplicar · ⌫ borrar · ⌘Z deshacer.
                Goma (E) y Recuperar (R) pintan sobre la capa seleccionada; [ y ] cambian el tamaño; V o Esc vuelven a mover.
                """)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .surfaceStyle(cornerRadius: 14)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 20).padding(.horizontal, 6)
    }

    private func renameProject() {
        let alert = NSAlert()
        alert.messageText = "Nombre del collage"
        alert.addButton(withTitle: "Guardar")
        alert.addButton(withTitle: "Cancelar")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = model.projectName.isEmpty ? CollageModel.defaultName() : model.projectName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            model.rename(field.stringValue)
        }
    }
}

private struct CollageBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: CollageModel
    @ObservedObject private var runner: ToolRunner

    init(model: CollageModel) {
        _model = ObservedObject(wrappedValue: model)
        _runner = ObservedObject(wrappedValue: model.runner)
    }

    var body: some View {
        ToolBarContainer {
            HStack(alignment: .top, spacing: 8) {
                TextField("Indicaciones extra (opcional): luz de tarde, más ordenado, estilo nórdico…",
                          text: $model.extraPrompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...3)
                    .padding(.horizontal, 6)
                    .padding(.top, 5)
                PromptEnhanceButton(text: $model.extraPrompt) {
                    PromptEnhancer.Context(kind: .edit, editField: .global)
                }
            }

            HStack(spacing: 8) {
                ChipPicker(icon: "viewfinder", title: "Resolución", options: Flux3Image.resolutions,
                           selection: $model.resolution, label: { Flux3Image.resolutionLabel($0) })
                ChipPicker(icon: "square.grid.2x2", title: "Número de imágenes", options: [1, 2, 3, 4],
                           selection: $model.count, label: { $0 == 1 ? "1 imagen" : "\($0) imágenes" })
                Button { model.sendOriginals.toggle() } label: {
                    Chip(icon: model.sendOriginals ? "checkmark.square" : "square",
                         text: "Enviar fotos originales", isActive: model.sendOriginals)
                }
                .buttonStyle(.plain)
                .help("Envía también las fotos de cada objeto como referencia, para que FLUX respete mejor cómo son (texturas, etiquetas). Máximo 9.")

                Spacer(minLength: 8)

                if runner.isRunning {
                    ProgressView().controlSize(.small)
                    Text(runner.runningCount > 1 ? "\(runner.runningCount) en marcha" : runner.status)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Button("Cancelar") { runner.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.danger)
                }

                Button { model.generate(state: state) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                        Text("Hacer realista").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.action.opacity(model.canGenerate ? 1 : 0.3)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canGenerate)
                .help(model.layers.isEmpty
                      ? "Añade al menos un objeto encima de la base"
                      : "Junta el collage y FLUX 3 Image lo convierte en una foto realista (⌘↩)")
            }
        }
    }
}

// MARK: - Vacío

private struct CollageEmptyState: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: CollageModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text("Collage")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Elige una foto base (por ejemplo, la librería del salón) y coloca encima objetos: libros, cuencos, lámparas… Muévelos, escálalos y ajusta su perspectiva. Después, «Hacer realista» lo convierte en una foto.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button {
                    if let url = chooseImages(allowsMultiple: false).first { model.setBase(url) }
                } label: {
                    Chip(icon: "photo", text: "Elegir foto base…", isActive: true)
                }
                .buttonStyle(.plain)
                if let url = state.focusedURL, !VideoModel.isVideo(url) {
                    Button { model.setBase(url) } label: {
                        Chip(icon: "photo.on.rectangle", text: "Usar la imagen seleccionada")
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("También puedes arrastrar una foto aquí o pegarla con ⌘V.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)

            if !model.recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Seguir con un collage guardado")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.recentProjects.prefix(12)) { project in
                                RecentCollageCard(project: project) { model.open(project, state: state) }
                                    .contextMenu {
                                        Button("Abrir") { model.open(project, state: state) }
                                        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([project.url]) }
                                        Button("Mover a la Papelera", role: .destructive) { model.deleteProject(project) }
                                    }
                            }
                        }
                    }
                }
                .frame(maxWidth: 720)
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.reloadRecentProjects() }
    }
}

private struct RecentCollageCard: View {
    let project: CollageProjectSummary
    let action: () -> Void
    @State private var thumbnail: NSImage?

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.placeholder)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        Image(systemName: "square.3.layers.3d").foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 150, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(project.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(project.layerCount) objetos · \(project.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 150)
        }
        .buttonStyle(.plain)
        .task(id: project.modified) {
            // Sin caché: la miniatura cambia cada vez que se guarda el collage.
            let url = project.preview
            thumbnail = await Task.detached { NSImage(contentsOf: url) }.value
        }
    }
}

/// «Quitar fondo» y su control: borde, suavizado, quitar el recorte y ajustar la caja.
private struct CutoutControls: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: CollageModel
    let layer: CollageLayer
    @State private var edge: Double = 0
    @State private var feather: Double = 1

    private var busy: Bool { model.cuttingOut.contains(layer.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if layer.autoMask == nil {
                Button { model.removeBackground(layer.id, state: state) } label: {
                    Label(busy ? "Quitando fondo…" : "Quitar fondo", systemImage: "wand.and.rays")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.region.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.region.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .help("Detecta el objeto con el recorte de sujetos de macOS (gratis, sin internet). No borra nada: después puedes ajustar el borde, recuperar partes con el pincel o quitar el recorte.")
                if layer.isCutOut {
                    // Capas recortadas con la versión anterior (la foto se sustituyó por el recorte).
                    Button("Volver a la foto original") { model.restoreOriginalPhoto(layer.id, state: state) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.region)
                }
            } else {
                HStack {
                    SectionLabel("Recorte")
                    Spacer()
                    Button("Quitar recorte") { model.removeCutout(layer.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .help("Vuelve a verse la foto entera (también lo borrado con la goma). ⌘Z lo deshace.")
                }
                slider("Borde", value: $edge, range: -20...20, hint: "Encoger (−) o agrandar (+) el recorte: + recupera lo que se ha comido, − quita restos de fondo.")
                slider("Suavizar", value: $feather, range: 0...10, hint: "Difumina el borde para que se integre mejor.")
                HStack(spacing: 10) {
                    Button("Ajustar caja al objeto") { model.fitBoxToContent(layer.id) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.region)
                        .help("Recorta la caja de la capa a lo que se ve, para moverla y escalarla más cómodamente.")
                }
                Text("Para retocar zonas concretas, usa Goma (E) o Recuperar (R). Si después mueves Borde o Suavizar, esos retoques se pierden.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { edge = layer.maskEdge; feather = layer.maskFeather }
        .onChange(of: layer.maskEdge) { edge = layer.maskEdge }
        .onChange(of: layer.maskFeather) { feather = layer.maskFeather }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, hint: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            // Se aplica al soltar, para que vaya fluido.
            Slider(value: value, in: range, onEditingChanged: { editing in
                if !editing { model.adjustCutout(layer.id, edge: edge, feather: feather) }
            })
            .controlSize(.mini)
            Text(String(format: "%+.0f", value.wrappedValue))
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 24, alignment: .trailing)
        }
        .help(hint)
    }
}
