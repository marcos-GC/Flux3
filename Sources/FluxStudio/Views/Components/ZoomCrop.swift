import AppKit
import SwiftUI

// MARK: - Estado de zoom y recorte

/// Zoom, desplazamiento y recorte de la imagen que se ve en grande (Generar y las demás
/// herramientas, Collage, y el recorte de Editar).
@MainActor
final class ViewerZoom: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    /// Recuadro de recorte, normalizado (0…1, origen arriba a la izquierda). Si no es nil, se está recortando.
    @Published var cropRect: CGRect?
    /// Proporción fija del recorte (ancho / alto en píxeles), o nil para libre.
    @Published var cropAspect: CGFloat?

    let minZoom: CGFloat
    let maxZoom: CGFloat = 8
    /// El puntero está encima de la imagen (para el zoom con la rueda y el pellizco).
    var pointerInside = false

    init(minZoom: CGFloat = 1) {
        self.minZoom = minZoom
    }

    var isCropping: Bool { cropRect != nil }

    func setZoom(_ value: CGFloat) {
        zoom = min(maxZoom, max(minZoom, value))
        if minZoom >= 1 && zoom <= 1 { pan = .zero }
    }

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func fit() { zoom = 1; pan = .zero }

    func reset() {
        fit()
        cropRect = nil
        cropAspect = nil
    }

    func startCrop() {
        cropAspect = nil
        cropRect = CGRect(x: 0.08, y: 0.08, width: 0.84, height: 0.84)
    }

    func cancelCrop() {
        cropRect = nil
        cropAspect = nil
    }

    /// Fija la proporción y pone el recuadro más grande posible, centrado.
    /// `imageAspect` es el ancho / alto de la imagen en píxeles.
    func setCropAspect(_ aspect: CGFloat?, imageAspect: CGFloat) {
        cropAspect = aspect
        guard let aspect, aspect > 0, imageAspect > 0 else { return }
        let k = imageAspect / aspect // alto normalizado por cada unidad de ancho normalizado
        var w: CGFloat = 0.9, h = w * k
        if h > 0.9 { h = 0.9; w = h / k }
        cropRect = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    /// Dónde queda la imagen (con zoom y desplazamiento) dentro de un marco donde se ve ajustada.
    func imageFrame(in size: CGSize) -> CGRect {
        let w = size.width * zoom, h = size.height * zoom
        return CGRect(x: (size.width - w) / 2 + pan.width, y: (size.height - h) / 2 + pan.height, width: w, height: h)
    }

    /// Rueda / trackpad: ⌘ + rueda o pellizco = zoom; dos dedos = desplazar (con zoom).
    /// Devuelve true si el evento se ha usado.
    func handle(_ event: NSEvent) -> Bool {
        guard pointerInside else { return false }
        switch event.type {
        case .scrollWheel:
            if event.modifierFlags.contains(.command) {
                setZoom(zoom * (1 + event.scrollingDeltaY * 0.01))
                return true
            }
            guard zoom != 1 else { return false }
            pan.width += event.scrollingDeltaX
            pan.height += event.scrollingDeltaY
            return true
        case .magnify:
            setZoom(zoom * (1 + event.magnification))
            return true
        default:
            return false
        }
    }
}

extension View {
    /// Zoom con ⌘ + rueda o pellizco y desplazamiento con dos dedos mientras el puntero está encima.
    func zoomEvents(_ viewer: ViewerZoom) -> some View {
        modifier(ZoomEventsModifier(viewer: viewer))
    }
}

private struct ZoomEventsModifier: ViewModifier {
    let viewer: ViewerZoom
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active: viewer.pointerInside = true
                case .ended: viewer.pointerInside = false
                }
            }
            .onAppear {
                guard monitor == nil else { return }
                let viewer = self.viewer
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
                    let consumed: Bool = MainActor.assumeIsolated { viewer.handle(event) }
                    return consumed ? nil : event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
                viewer.pointerInside = false
            }
    }
}

// MARK: - Botones

/// − 100 % + y «Ajustar», solo con iconos.
struct ZoomButtons: View {
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize
    var minZoom: CGFloat = 0.2
    var maxZoom: CGFloat = 8
    var axis: Axis = .horizontal

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ToolIconButton(icon: "minus.magnifyingglass", help: "Alejar (⌘ + rueda o pellizco)") {
                set(zoom / 1.25)
            }
            .disabled(zoom <= minZoom + 0.001)
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .frame(width: axis == .vertical ? 34 : 40, height: axis == .vertical ? 20 : nil)
                .help("Zoom: ⌘ + rueda o pellizco. Desplazar: dos dedos en el trackpad.")
            ToolIconButton(icon: "plus.magnifyingglass", help: "Acercar (⌘ + rueda o pellizco)") {
                set(zoom * 1.25)
            }
            .disabled(zoom >= maxZoom - 0.001)
            ToolIconButton(icon: "arrow.down.right.and.arrow.up.left",
                           help: "Ajustar a la ventana") {
                zoom = 1
                pan = .zero
            }
            .disabled(zoom == 1 && pan == .zero)
        }
    }

    private func set(_ value: CGFloat) {
        zoom = min(maxZoom, max(minZoom, value))
        if minZoom >= 1 && zoom <= 1 { pan = .zero }
    }
}

/// Mientras se recorta: proporción, cancelar y aplicar.
struct CropActionButtons: View {
    @ObservedObject var viewer: ViewerZoom
    /// Ancho / alto de la imagen en píxeles.
    let imageAspect: CGFloat
    var axis: Axis = .horizontal
    let onApply: () -> Void

    private struct Preset: Identifiable {
        let name: String
        let aspect: CGFloat?
        var id: String { name }
    }

    private static let presets: [Preset] = [
        Preset(name: "Libre", aspect: nil), Preset(name: "1:1", aspect: 1),
        Preset(name: "4:5", aspect: 4.0 / 5), Preset(name: "3:4", aspect: 3.0 / 4),
        Preset(name: "4:3", aspect: 4.0 / 3), Preset(name: "3:2", aspect: 3.0 / 2),
        Preset(name: "2:3", aspect: 2.0 / 3), Preset(name: "16:9", aspect: 16.0 / 9),
        Preset(name: "9:16", aspect: 9.0 / 16),
    ]

    var body: some View {
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            Menu {
                ForEach(Self.presets) { preset in
                    Button {
                        if let aspect = preset.aspect {
                            viewer.setCropAspect(aspect, imageAspect: imageAspect)
                        } else {
                            viewer.cropAspect = nil
                        }
                    } label: {
                        if isSelected(preset.aspect) {
                            Label(preset.name, systemImage: "checkmark")
                        } else {
                            Text(preset.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "aspectratio")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 30, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Proporción del recorte")
            ToolIconButton(icon: "xmark", help: "Cancelar el recorte (Esc)") { viewer.cancelCrop() }
                .keyboardShortcut(.escape, modifiers: [])
            Button(action: onApply) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.action))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            .help("Recortar (↩). El recorte se guarda como imagen nueva en la tira; la original no cambia.")
            .padding(axis == .vertical ? Edge.Set.vertical : Edge.Set.leading, 3)
        }
    }

    private func isSelected(_ aspect: CGFloat?) -> Bool {
        switch (aspect, viewer.cropAspect) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) < 0.001
        default: return false
        }
    }
}

// MARK: - Recuadro de recorte

/// Recuadro de recorte encima de una imagen: oscurece lo que queda fuera y se mueve
/// y redimensiona desde dentro y desde las esquinas.
struct CropOverlay: View {
    @ObservedObject var viewer: ViewerZoom
    /// Dónde está la imagen, en el espacio de coordenadas `space`.
    let frame: CGRect
    let space: String
    /// Ancho / alto de la imagen en píxeles (para mantener la proporción elegida).
    let imageAspect: CGFloat

    @State private var start: CGRect?

    private enum Handle: Hashable, CaseIterable {
        case move, topLeft, topRight, bottomLeft, bottomRight
    }

    var body: some View {
        let rect = viewer.cropRect ?? .zero
        let vr = CGRect(
            x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height,
            width: rect.width * frame.width, height: rect.height * frame.height
        )
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(frame)
                path.addRect(vr)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // Tercios.
            Path { path in
                for i in 1...2 {
                    let x = vr.minX + vr.width * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: vr.minY)); path.addLine(to: CGPoint(x: x, y: vr.maxY))
                    let y = vr.minY + vr.height * CGFloat(i) / 3
                    path.move(to: CGPoint(x: vr.minX, y: y)); path.addLine(to: CGPoint(x: vr.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.55), lineWidth: 0.5)
            .allowsHitTesting(false)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1.5))
                .frame(width: max(vr.width, 1), height: max(vr.height, 1))
                .contentShape(Rectangle())
                .gesture(drag(.move))
                .offset(x: vr.minX, y: vr.minY)

            ForEach([Handle.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { handle in
                let p = point(handle, in: vr)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle().inset(by: -6))
                    .gesture(drag(handle))
                    .offset(x: p.x - 7, y: p.y - 7)
            }

            if let px = pixelSizeText(rect) {
                Text(px)
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .fixedSize()
                    .offset(x: vr.minX + 6, y: vr.minY + 6)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Proporción aproximada del recorte, para saber qué se está cortando.
    private func pixelSizeText(_ rect: CGRect) -> String? {
        guard rect.width > 0, rect.height > 0, imageAspect > 0 else { return nil }
        let ratio = rect.width / rect.height * imageAspect
        return String(format: "%.2f : 1", ratio)
    }

    private func point(_ handle: Handle, in r: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: r.minX, y: r.minY)
        case .topRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .bottomRight, .move: return CGPoint(x: r.maxX, y: r.maxY)
        }
    }

    private func drag(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                if start == nil { start = viewer.cropRect }
                guard let s = start, frame.width > 0, frame.height > 0 else { return }
                let dx = value.translation.width / frame.width
                let dy = value.translation.height / frame.height
                viewer.cropRect = Self.resized(s, handle: handle, dx: dx, dy: dy,
                                               aspect: viewer.cropAspect, imageAspect: imageAspect)
            }
            .onEnded { _ in start = nil }
    }

    private static func resized(_ s: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat,
                                aspect: CGFloat?, imageAspect: CGFloat) -> CGRect {
        let minSize: CGFloat = 0.03
        if handle == .move {
            let x = min(max(0, s.minX + dx), 1 - s.width)
            let y = min(max(0, s.minY + dy), 1 - s.height)
            return CGRect(x: x, y: y, width: s.width, height: s.height)
        }
        let right = handle == .topRight || handle == .bottomRight
        let down = handle == .bottomLeft || handle == .bottomRight
        // La esquina contraria se queda fija.
        let anchor = CGPoint(x: right ? s.minX : s.maxX, y: down ? s.minY : s.maxY)

        if let aspect, aspect > 0, imageAspect > 0 {
            let k = imageAspect / aspect
            var w = right ? s.maxX + dx - anchor.x : anchor.x - (s.minX + dx)
            let maxW = right ? 1 - anchor.x : anchor.x
            let maxH = down ? 1 - anchor.y : anchor.y
            w = min(max(w, minSize), maxW, maxH / k)
            let h = w * k
            return CGRect(x: right ? anchor.x : anchor.x - w, y: down ? anchor.y : anchor.y - h, width: w, height: h)
        }

        var minX = s.minX, minY = s.minY, maxX = s.maxX, maxY = s.maxY
        if right { maxX += dx } else { minX += dx }
        if down { maxY += dy } else { minY += dy }
        minX = max(0, min(minX, maxX - minSize))
        minY = max(0, min(minY, maxY - minSize))
        maxX = min(1, max(maxX, minX + minSize))
        maxY = min(1, max(maxY, minY + minSize))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
