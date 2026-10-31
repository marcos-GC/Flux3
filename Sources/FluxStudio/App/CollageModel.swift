import AppKit
import CoreImage
import FluxCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision

/// Una capa del collage: una imagen colocada sobre la base con su cuadrilátero.
struct CollageLayer: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    /// Imagen (reducida si era muy grande) que se pinta y se usa al aplanar.
    var cgImage: CGImage
    var image: NSImage
    var quad: CollageQuad
    var opacity: Double = 1
    var isVisible = true
    /// Se le ha quitado el fondo.
    var isCutOut = false

    var name: String { sourceURL.deletingPathExtension().lastPathComponent }

    static func == (l: CollageLayer, r: CollageLayer) -> Bool {
        l.id == r.id && l.quad == r.quad && l.opacity == r.opacity && l.isVisible == r.isVisible
            && l.cgImage === r.cgImage
    }
}

/// Imagen base del collage (fija el tamaño del lienzo).
struct CollageBase {
    let url: URL
    let cgImage: CGImage
    let image: NSImage
    var size: CGSize { CGSize(width: cgImage.width, height: cgImage.height) }
}

/// Collage: una foto base y capas encima que se mueven, escalan, estiran, giran y deforman
/// en perspectiva. «Hacer realista» lo aplana y lo envía a FLUX 3 Image para integrarlo.
@MainActor
final class CollageModel: ObservableObject {
    @Published private(set) var base: CollageBase?
    @Published var layers: [CollageLayer] = []
    @Published var selectedID: UUID?
    @Published var extraPrompt = ""
    @Published var resolution = "2k"
    @Published var count = 1
    @Published var safety = SafetyTolerance.defaultValue
    @Published var sendOriginals = true
    @Published private(set) var cuttingOut: Set<UUID> = []
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    let runner = ToolRunner()
    private let settings: SettingsStore
    private var undoStack: [[CollageLayer]] = []
    private var redoStack: [[CollageLayer]] = []

    /// Tamaño máximo de la base y de las capas (en píxeles, lado largo).
    static let maxBaseSide = 3072
    static let maxLayerSide = 2048

    init(settings: SettingsStore) {
        self.settings = settings
        self.safety = SafetyTolerance.clamp(settings.defaultSafety, for: .flux3Image)
    }

    var selected: CollageLayer? { layers.first { $0.id == selectedID } }
    var canvasSize: CGSize { base?.size ?? CGSize(width: 1536, height: 1024) }

    // MARK: Cargar

    func setBase(_ url: URL) {
        guard let cg = ImageEncoder.thumbnail(fileURL: url, maxPixelSize: Self.maxBaseSide) else { return }
        let newBase = CollageBase(url: url, cgImage: cg, image: NSImage(cgImage: cg, size: .zero))
        // Si ya había capas, se reescalan para que sigan en el mismo sitio relativo.
        if let old = base, old.size.width > 0 {
            let factor = newBase.size.width / old.size.width
            if abs(factor - 1) > 0.001 {
                layers = layers.map { var l = $0; l.quad = l.quad.scaled(by: factor); return l }
            }
        }
        base = newBase
        resolution = Self.suggestedResolution(for: newBase.size)
    }

    /// Añade imágenes como capas. Si aún no hay base, la primera pasa a ser la base.
    func add(_ urls: [URL]) {
        var pending = urls.filter(ReferenceImage.isSupported)
        guard !pending.isEmpty else { return }
        if base == nil { setBase(pending.removeFirst()) }
        guard !pending.isEmpty else { return }
        pushUndo()
        for (i, url) in pending.enumerated() {
            guard let cg = ImageEncoder.thumbnail(fileURL: url, maxPixelSize: Self.maxLayerSide) else { continue }
            let size = canvasSize
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            // Cabe en un 35 % del lienzo, centrada (las siguientes, un poco desplazadas).
            let fit = min(size.width * 0.35 / w, size.height * 0.35 / h, 1)
            let shift = CGFloat((layers.count + i) % 6) * size.width * 0.03
            let rect = CGRect(x: (size.width - w * fit) / 2 + shift, y: (size.height - h * fit) / 2 + shift,
                              width: w * fit, height: h * fit)
            let layer = CollageLayer(id: UUID(), sourceURL: url, cgImage: cg,
                                     image: NSImage(cgImage: cg, size: .zero), quad: CollageQuad(rect: rect))
            layers.append(layer)
            selectedID = layer.id
        }
    }

    func reset() {
        base = nil
        layers = []
        selectedID = nil
        extraPrompt = ""
        undoStack = []
        redoStack = []
        updateUndoFlags()
    }

    static func suggestedResolution(for size: CGSize) -> String {
        let mp = size.width * size.height / 1_000_000
        switch mp {
        case ..<1.3: return "1k"
        case ..<3: return "1.5k"
        case ..<7: return "2k"
        default: return "4k"
        }
    }

    // MARK: Capas

    func update(_ id: UUID, _ change: (inout CollageLayer) -> Void) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        change(&layers[i])
    }

    /// Para cambios de un solo paso (botones): guarda el estado para deshacer y aplica.
    func edit(_ id: UUID, _ change: (inout CollageLayer) -> Void) {
        pushUndo()
        update(id, change)
    }

    func remove(_ id: UUID) {
        pushUndo()
        layers.removeAll { $0.id == id }
        if selectedID == id { selectedID = layers.last?.id }
    }

    func duplicate(_ id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        var copy = layers[index]
        copy = CollageLayer(id: UUID(), sourceURL: copy.sourceURL, cgImage: copy.cgImage, image: copy.image,
                            quad: copy.quad.translated(by: CGVector(dx: canvasSize.width * 0.03, dy: canvasSize.width * 0.03)),
                            opacity: copy.opacity, isVisible: true, isCutOut: copy.isCutOut)
        layers.insert(copy, at: index + 1)
        selectedID = copy.id
    }

    /// Sube (+1, hacia delante) o baja (-1, hacia atrás) una capa.
    func move(_ id: UUID, by step: Int) {
        guard let i = layers.firstIndex(where: { $0.id == id }) else { return }
        let j = i + step
        guard layers.indices.contains(j) else { return }
        pushUndo()
        layers.swapAt(i, j)
    }

    /// Quita giros, estiramientos y perspectiva, manteniendo el centro y el ancho aproximado.
    func resetTransform(_ id: UUID) {
        guard let layer = layers.first(where: { $0.id == id }) else { return }
        let rect = Self.uprightRect(for: layer.cgImage, width: layer.quad.approximateSize.width, center: layer.quad.center)
        edit(id) { $0.quad = CollageQuad(rect: rect) }
    }

    private static func uprightRect(for image: CGImage, width: CGFloat, center c: CGPoint) -> CGRect {
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        return CGRect(x: c.x - width / 2, y: c.y - width * aspect / 2, width: width, height: width * aspect)
    }

    /// Capa más alta (visible) bajo un punto del lienzo.
    func layer(at point: CGPoint) -> CollageLayer? {
        layers.last { $0.isVisible && $0.quad.contains(point) }
    }

    // MARK: Quitar fondo

    /// Recorta el objeto principal con el recorte de sujetos de macOS (Vision), sin gastar créditos.
    func removeBackground(_ id: UUID, state: AppState) {
        guard let layer = layers.first(where: { $0.id == id }), !cuttingOut.contains(id) else { return }
        cuttingOut.insert(id)
        let source = layer.cgImage
        Task {
            let cut = await Task.detached(priority: .userInitiated) { Self.cutOut(source) }.value
            cuttingOut.remove(id)
            guard let cut else {
                state.alert = AppAlert(
                    title: "No se ha podido quitar el fondo",
                    message: "No se ha encontrado un objeto claro en «\(layer.name)». Funciona mejor con un objeto bien definido sobre un fondo distinto."
                )
                return
            }
            guard let current = layers.first(where: { $0.id == id }) else { return }
            // Mantiene la escala en pantalla: mismos píxeles de pantalla por píxel de imagen.
            let scale = current.quad.approximateSize.width / CGFloat(max(current.cgImage.width, 1))
            let rect = Self.uprightRect(for: cut, width: CGFloat(cut.width) * scale,
                                        center: current.quad.center)
            edit(id) {
                $0.cgImage = cut
                $0.image = NSImage(cgImage: cut, size: .zero)
                $0.quad = CollageQuad(rect: rect)
                $0.isCutOut = true
            }
        }
    }

    nonisolated private static func cutOut(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true
            )
            let ci = CIImage(cvPixelBuffer: buffer)
            let context = CIContext()
            guard let cg = context.createCGImage(ci, from: ci.extent, format: .RGBA8,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
            return cg
        } catch {
            return nil
        }
    }

    // MARK: Deshacer

    func pushUndo() {
        undoStack.append(layers)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
        updateUndoFlags()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(layers)
        layers = previous
        if let id = selectedID, !layers.contains(where: { $0.id == id }) { selectedID = nil }
        updateUndoFlags()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(layers)
        layers = next
        updateUndoFlags()
    }

    private func updateUndoFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Aplanar

    /// Junta base y capas visibles en una sola imagen del tamaño de la base.
    func flatten() -> CGImage? {
        guard let base else { return nil }
        let height = base.size.height
        var result = CIImage(cgImage: base.cgImage)
        let extent = result.extent
        for layer in layers where layer.isVisible && layer.opacity > 0 {
            // Core Image cuenta la y desde abajo.
            func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: height - p.y) }
            guard let filter = CIFilter(name: "CIPerspectiveTransform") else { continue }
            filter.setValue(CIImage(cgImage: layer.cgImage), forKey: kCIInputImageKey)
            filter.setValue(v(layer.quad.topLeft), forKey: "inputTopLeft")
            filter.setValue(v(layer.quad.topRight), forKey: "inputTopRight")
            filter.setValue(v(layer.quad.bottomRight), forKey: "inputBottomRight")
            filter.setValue(v(layer.quad.bottomLeft), forKey: "inputBottomLeft")
            guard var warped = filter.outputImage else { continue }
            if layer.opacity < 1 {
                warped = warped.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(layer.opacity)),
                ])
            }
            result = warped.composited(over: result)
        }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.workingColorSpace: sRGB])
        return context.createCGImage(result.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: sRGB)
    }

    /// Guarda el collage aplanado en «<carpeta de salida>/Collages» y devuelve su archivo.
    func saveFlattened() throws -> URL {
        guard let image = flatten() else { throw ImageEncoder.EncodeError.unreadable }
        let folder = settings.outputFolder.appendingPathComponent("Collages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = folder.appendingPathComponent("collage_\(formatter.string(from: Date())).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageEncoder.EncodeError.unreadable
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageEncoder.EncodeError.unreadable }
        return url
    }

    // MARK: Hacer realista

    var canGenerate: Bool { base != nil && layers.contains(where: \.isVisible) && cuttingOut.isEmpty }

    func generate(state: AppState) {
        guard canGenerate else { return }
        let collageURL: URL
        do {
            collageURL = try saveFlattened()
        } catch {
            state.alert = AppAlert(title: "No se ha podido preparar el collage", message: error.localizedDescription)
            return
        }
        // Fotos originales de los objetos (sin repetir y como mucho las que admite FLUX).
        var originals: [URL] = []
        if sendOriginals {
            for layer in layers where layer.isVisible && !originals.contains(layer.sourceURL) {
                originals.append(layer.sourceURL)
            }
            originals = Array(originals.prefix(Flux3Image.maxReferenceImages - 1))
        }
        let refs = originals
        let prompt = CollagePrompt.build(extra: extraPrompt, referenceCount: refs.count)
        let note = extraPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = note.isEmpty ? "Collage realista (\(layers.filter(\.isVisible).count) objetos)" : "Collage realista: \(note)"
        let res = resolution, st = safety
        for _ in 0..<max(1, min(4, count)) {
            runner.run(
                state: state, endpoint: .flux3Image, modelName: "Collage", prompt: summary,
                referenceCount: refs.count, source: collageURL,
                onDone: { url in
                    // Aviso «Listo · Ver» aunque sigas en el collage.
                    if state.tool == .collage { state.readyNotice = ReadyNotice(url: url, label: "Collage realista") }
                }
            ) {
                let images = try await Task.detached(priority: .userInitiated) { () -> [String] in
                    var list = [try ImageEncoder.encode(fileURL: collageURL).base64]
                    for url in refs {
                        if let encoded = try? ImageEncoder.encode(fileURL: url) { list.append(encoded.base64) }
                    }
                    return list
                }.value
                return Flux3ImageRequest(prompt: prompt, images: images, aspectRatio: "auto",
                                         resolution: res, safetyTolerance: st, grounding: false)
            }
        }
    }
}
