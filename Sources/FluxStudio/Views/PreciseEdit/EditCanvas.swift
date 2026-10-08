import AppKit
import FluxCore
import SwiftUI

/// Lienzo con la imagen, zoom/pan y las regiones dibujadas encima.
struct EditCanvas: View {
    @EnvironmentObject private var model: PreciseEditModel
    @State private var drawStart: CGPoint?
    @State private var drawCurrent: CGPoint?
    @State private var panStart: CGSize?
    @State private var monitor: Any?
    @State private var compareFraction: CGFloat = 0.5

    /// Márgenes que dejan sitio a las barras flotantes.
    private let insets = EdgeInsets(top: 28, leading: 40, bottom: 270, trailing: 40)

    var body: some View {
        GeometryReader { geo in
            if let version = model.current {
                let layout = CanvasLayout(container: geo.size, insets: insets, image: version.pixelSize, zoom: model.zoom, pan: model.pan)
                ZStack(alignment: .topLeading) {
                    // Fondo: dibujar regiones (arrastrar), pan (espacio + arrastrar) y deseleccionar (clic).
                    Theme.background
                        .contentShape(Rectangle())
                        .gesture(backgroundDrag(layout))
                        .onTapGesture { model.selectedRegionID = nil }

                    if model.compareMode, let before = model.parentOfCurrent {
                        CompareView(before: before.image, after: version.image, fraction: $compareFraction)
                            .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                            .offset(x: layout.imageFrame.minX, y: layout.imageFrame.minY)
                    } else {
                        Image(nsImage: version.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: layout.imageFrame.width, height: layout.imageFrame.height)
                            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                            .offset(x: layout.imageFrame.minX, y: layout.imageFrame.minY)
                            .allowsHitTesting(false)

                        if model.showRegions {
                            regionsLayer(layout)
                        }
                        if let rect = drawingRect(layout) {
                            Rectangle()
                                .fill(Theme.region.opacity(0.12))
                                .overlay(Rectangle().strokeBorder(Theme.region, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                                .frame(width: rect.width, height: rect.height)
                                .offset(x: rect.minX, y: rect.minY)
                                .allowsHitTesting(false)
                        }
                        if model.showRegions, let id = model.selectedRegionID,
                           let region = model.regions.first(where: { $0.id == id }) {
                            RegionInspector(region: region)
                                .frame(width: 300)
                                .offset(inspectorOffset(for: region, layout: layout, container: geo.size))
                        }
                    }

                }
                .coordinateSpace(name: "canvas")
                .clipped()
                .onContinuousHover { phase in
                    switch phase {
                    case .active: model.pointerInCanvas = true
                    case .ended: model.pointerInCanvas = false
                    }
                }
            }
        }
        .onAppear(perform: installMonitor)
        .onDisappear(perform: removeMonitor)
    }

    // MARK: Regiones

    @ViewBuilder
    private func regionsLayer(_ layout: CanvasLayout) -> some View {
        ForEach(Array(model.regions.enumerated()), id: \.element.id) { index, region in
            let selected = model.selectedRegionID == region.id
            BoxEditor(
                rect: rectBinding(region.id, target: false),
                layout: layout,
                label: "\(index + 1)",
                caption: region.kind == .new ? "Nuevo: \(region.displayText)" : region.displayText,
                style: region.kind == .anchor ? .anchor : .primary,
                color: Theme.regionColor(index, kind: region.kind),
                selected: selected
            ) { model.selectedRegionID = region.id }

            if region.kind == .move, region.target != nil {
                BoxEditor(
                    rect: rectBinding(region.id, target: true),
                    layout: layout,
                    label: "\(index + 1)→",
                    caption: "Destino",
                    style: .target,
                    color: Theme.regionColor(index),
                    selected: selected
                ) { model.selectedRegionID = region.id }
            }
        }
    }

    private func rectBinding(_ id: UUID, target: Bool) -> Binding<CGRect> {
        Binding(
            get: {
                let region = model.regions.first { $0.id == id }
                return (target ? region?.target : region?.rect) ?? .zero
            },
            set: { newValue in
                model.update(id) { region in
                    if target { region.target = newValue } else { region.rect = newValue }
                }
            }
        )
    }

    private func inspectorOffset(for region: RegionDraft, layout: CanvasLayout, container: CGSize) -> CGSize {
        let box = layout.viewRect(region.target.map { region.rect.union($0) } ?? region.rect)
        let width: CGFloat = 300, height: CGFloat = 250
        var x = box.maxX + 14
        if x + width > container.width - 12 { x = box.minX - width - 14 }
        x = min(max(12, x), container.width - width - 12)
        let y = min(max(16, box.minY), container.height - height - 260)
        return CGSize(width: x, height: y)
    }

    // MARK: Dibujar / pan

    private func backgroundDrag(_ layout: CanvasLayout) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if model.spaceHeld || panStart != nil {
                    if panStart == nil { panStart = model.pan }
                    model.pan = CGSize(width: panStart!.width + value.translation.width,
                                       height: panStart!.height + value.translation.height)
                    return
                }
                guard !model.compareMode else { return }
                if drawStart == nil { drawStart = value.startLocation }
                drawCurrent = value.location
            }
            .onEnded { _ in
                defer { drawStart = nil; drawCurrent = nil; panStart = nil }
                guard panStart == nil, let rect = drawingRect(layout) else { return }
                let normalized = layout.normalizedRect(rect)
                if normalized.width > 0.01 && normalized.height > 0.01 {
                    model.addRegion(normalized)
                }
            }
    }

    private func drawingRect(_ layout: CanvasLayout) -> CGRect? {
        guard let a = drawStart, let b = drawCurrent else { return nil }
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        return rect.intersection(layout.imageFrame).isNull ? nil : rect.intersection(layout.imageFrame)
    }

    // MARK: Teclado y trackpad

    private func installMonitor() {
        guard monitor == nil else { return }
        let model = self.model
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .scrollWheel, .magnify]) { event in
            let consumed: Bool = MainActor.assumeIsolated { Self.handle(event, model: model) }
            return consumed ? nil : event
        }
    }

    /// Devuelve true si el evento se ha usado (y no debe llegar a otras vistas).
    @MainActor
    private static func handle(_ event: NSEvent, model: PreciseEditModel) -> Bool {
        let editingText = NSApp.keyWindow?.firstResponder is NSText
        switch event.type {
        case .keyDown where event.keyCode == 49 && !editingText && model.pointerInCanvas:
            model.spaceHeld = true
            NSCursor.openHand.set()
            return true
        case .keyUp where event.keyCode == 49 && model.spaceHeld:
            model.spaceHeld = false
            NSCursor.arrow.set()
            return true
        case .keyDown where (event.keyCode == 51 || event.keyCode == 117) && !editingText:
            // Borrar la región seleccionada con ⌫ / Supr.
            if let id = model.selectedRegionID { model.removeRegion(id); return true }
            return false
        case .scrollWheel where model.pointerInCanvas:
            if event.modifierFlags.contains(.command) {
                let factor = 1 + event.scrollingDeltaY * 0.01
                model.zoom = min(8, max(0.2, model.zoom * factor))
            } else {
                model.pan.width += event.scrollingDeltaX
                model.pan.height += event.scrollingDeltaY
            }
            return true
        case .magnify where model.pointerInCanvas:
            model.zoom = min(8, max(0.2, model.zoom * (1 + event.magnification)))
            return true
        default:
            return false
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        model.spaceHeld = false
    }
}

/// Geometría del lienzo: dónde se pinta la imagen y cómo se pasa de pantalla a coordenadas normalizadas.
struct CanvasLayout {
    let fitScale: CGFloat
    let imageFrame: CGRect

    init(container: CGSize, insets: EdgeInsets, image: CGSize, zoom: CGFloat, pan: CGSize) {
        let availW = max(100, container.width - insets.leading - insets.trailing)
        let availH = max(100, container.height - insets.top - insets.bottom)
        let w = max(image.width, 1), h = max(image.height, 1)
        fitScale = min(availW / w, availH / h)
        let scale = fitScale * zoom
        let size = CGSize(width: w * scale, height: h * scale)
        let cx = insets.leading + availW / 2 + pan.width
        let cy = insets.top + availH / 2 + pan.height
        imageFrame = CGRect(x: cx - size.width / 2, y: cy - size.height / 2, width: size.width, height: size.height)
    }

    func viewRect(_ normalized: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + normalized.minX * imageFrame.width,
            y: imageFrame.minY + normalized.minY * imageFrame.height,
            width: normalized.width * imageFrame.width,
            height: normalized.height * imageFrame.height
        )
    }

    func normalizedRect(_ view: CGRect) -> CGRect {
        CGRect(
            x: (view.minX - imageFrame.minX) / imageFrame.width,
            y: (view.minY - imageFrame.minY) / imageFrame.height,
            width: view.width / imageFrame.width,
            height: view.height / imageFrame.height
        ).clampedToUnit
    }
}

// MARK: - Caja editable

struct BoxEditor: View {
    enum Style { case primary, target, anchor }

    @Binding var rect: CGRect
    let layout: CanvasLayout
    let label: String
    let caption: String
    let style: Style
    var color: Color = Theme.region
    let selected: Bool
    let onSelect: () -> Void

    @State private var startRect: CGRect?

    private var tint: Color {
        switch style {
        case .primary: return color
        case .target: return color.opacity(0.75)
        case .anchor: return Theme.anchorColor
        }
    }

    var body: some View {
        let vr = layout.viewRect(rect)
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(tint.opacity(selected ? 0.16 : (style == .target ? 0.04 : 0.08)))
                .overlay(
                    Rectangle().strokeBorder(
                        tint,
                        style: StrokeStyle(lineWidth: selected ? 2.5 : 2, dash: style == .target ? [3, 4] : [7, 4])
                    )
                )
                .frame(width: max(vr.width, 4), height: max(vr.height, 4))
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                .gesture(moveGesture)
                .offset(x: vr.minX, y: vr.minY)

            // Etiqueta numerada encima de la caja.
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(tint))
                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            .padding(.trailing, 7)
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.92)))
            .fixedSize()
            .offset(x: vr.minX, y: vr.minY - 26)
            .onTapGesture(perform: onSelect)

            if selected {
                ForEach(Corner.allCases, id: \.self) { corner in
                    let p = corner.point(in: vr)
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(tint, lineWidth: 2))
                        .frame(width: 12, height: 12)
                        .contentShape(Rectangle().inset(by: -6))
                        .gesture(resizeGesture(corner))
                        .offset(x: p.x - 6, y: p.y - 6)
                }
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if startRect == nil { startRect = rect; onSelect() }
                guard let start = startRect else { return }
                var r = start
                r.origin.x += value.translation.width / layout.imageFrame.width
                r.origin.y += value.translation.height / layout.imageFrame.height
                rect = r.clampedToUnit
            }
            .onEnded { _ in startRect = nil }
    }

    private func resizeGesture(_ corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if startRect == nil { startRect = rect }
                guard let start = startRect else { return }
                let dx = value.translation.width / layout.imageFrame.width
                let dy = value.translation.height / layout.imageFrame.height
                var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
                switch corner {
                case .topLeft: minX += dx; minY += dy
                case .topRight: maxX += dx; minY += dy
                case .bottomLeft: minX += dx; maxY += dy
                case .bottomRight: maxX += dx; maxY += dy
                }
                let minSize = 0.01
                minX = max(0, min(minX, maxX - minSize))
                minY = max(0, min(minY, maxY - minSize))
                maxX = min(1, max(maxX, minX + minSize))
                maxY = min(1, max(maxY, minY + minSize))
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in startRect = nil }
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func point(in r: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: r.minX, y: r.minY)
            case .topRight: return CGPoint(x: r.maxX, y: r.minY)
            case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
            case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
            }
        }
    }
}

// MARK: - Zoom

/// Zoom del lienzo (100 % = imagen ajustada a la ventana).
struct ZoomControls: View {
    @EnvironmentObject private var model: PreciseEditModel

    var body: some View {
        HStack(spacing: 2) {
            button("minus") { model.zoom = max(0.2, model.zoom / 1.25) }
            Text("\(Int((model.zoom * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 46)
            button("plus") { model.zoom = min(8, model.zoom * 1.25) }
            Rectangle().fill(Theme.border).frame(width: 1, height: 16).padding(.horizontal, 4)
            Button("Ajustar") { model.zoom = 1; model.pan = .zero }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .padding(.trailing, 6)
        }
        .foregroundStyle(Theme.textPrimary)
        .help("Zoom: ⌘ + rueda o pellizco. Desplazar: espacio + arrastrar, o dos dedos en el trackpad.")
    }

    private func button(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Antes / Después

struct CompareView: View {
    let before: NSImage
    let after: NSImage
    @Binding var fraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Image(nsImage: after).resizable()
                Image(nsImage: before).resizable()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * fraction)
                    }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2)
                    .shadow(radius: 2)
                    .offset(x: geo.size.width * fraction - 1)
                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 12, weight: .bold)))
                    .shadow(radius: 3)
                    .offset(x: geo.size.width * fraction - 15, y: geo.size.height / 2 - 15)
                label("ANTES").offset(x: 10, y: 10)
                label("DESPUÉS").offset(x: geo.size.width - 84, y: 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { fraction = min(1, max(0, $0.location.x / geo.size.width)) }
            )
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .frame(width: 74)
    }
}
