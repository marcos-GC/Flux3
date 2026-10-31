import AppKit
import Combine
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
    /// Imagen de partida de la capa (reducida si era muy grande; ya recortada si se quitó el fondo).
    private(set) var original: CGImage
    /// Máscara de la goma (gris, mismo tamaño: blanco = se ve). nil = no se ha borrado nada.
    private(set) var mask: CGImage?
    /// Lo que se pinta y se aplana: `original` con la máscara aplicada.
    private(set) var cgImage: CGImage
    private(set) var image: NSImage
    var quad: CollageQuad
    var opacity: Double = 1
    var isVisible = true
    /// Se le ha quitado el fondo.
    var isCutOut = false
    /// Cambian cuando cambia la imagen o la máscara (nombres de archivo al guardar).
    private(set) var originalToken = CollageLayer.newToken()
    private(set) var maskToken = CollageLayer.newToken()

    static func newToken() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    init(id: UUID = UUID(), sourceURL: URL, original: CGImage, mask: CGImage? = nil, quad: CollageQuad,
         opacity: Double = 1, isVisible: Bool = true, isCutOut: Bool = false) {
        self.id = id
        self.sourceURL = sourceURL
        self.original = original
        self.mask = mask
        let shown = mask.flatMap { Self.composite(original, mask: $0) } ?? original
        self.cgImage = shown
        self.image = NSImage(cgImage: shown, size: .zero)
        self.quad = quad
        self.opacity = opacity
        self.isVisible = isVisible
        self.isCutOut = isCutOut
    }

    /// Cambia la máscara de la goma (nil = todo visible) y recalcula la imagen.
    mutating func setMask(_ newMask: CGImage?) {
        mask = newMask
        maskToken = Self.newToken()
        let shown = newMask.flatMap { Self.composite(original, mask: $0) } ?? original
        cgImage = shown
        image = NSImage(cgImage: shown, size: .zero)
    }

    /// Nueva imagen de partida (p. ej. tras quitar el fondo); la goma empieza de cero.
    mutating func setOriginal(_ newOriginal: CGImage) {
        original = newOriginal
        originalToken = Self.newToken()
        setMask(nil)
    }

    /// Solo la imagen mostrada, sin tocar la máscara (vista previa mientras se pinta).
    mutating func setPreview(_ shown: CGImage) {
        cgImage = shown
        image = NSImage(cgImage: shown, size: .zero)
    }

    /// `original` recortada por la máscara (blanco = se ve, negro = borrado).
    static func composite(_ original: CGImage, mask: CGImage) -> CGImage? {
        let w = original.width, h = original.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.clip(to: rect, mask: mask)
        ctx.draw(original, in: rect)
        return ctx.makeImage()
    }

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

    // Goma
    enum BrushMode: Equatable { case erase, restore }
    /// nil = transformar; si no, la goma o el pincel de recuperar sobre la capa seleccionada.
    @Published var brushMode: BrushMode?
    /// Diámetro del pincel en puntos de pantalla.
    @Published var brushSize: CGFloat = 40
    private var stroke: (layerID: UUID, context: CGContext, last: CGPoint?, lastPreview: Date)?

    // Proyecto
    @Published private(set) var projectName = ""
    @Published private(set) var recentProjects: [CollageProjectSummary] = []
    private(set) var projectURL: URL?
    private var projectCreated = Date()
    private var autosave: AnyCancellable?
    private var lastSavedSignature: String?
    /// Archivos de imagen que ya están escritos en la carpeta del proyecto.
    private var savedImages: Set<String> = []
    private var saveChain: Task<Void, Never>?
    private var undoStack: [[CollageLayer]] = []
    private var redoStack: [[CollageLayer]] = []

    /// Tamaño máximo de la base y de las capas (en píxeles, lado largo).
    static let maxBaseSide = 3072
    static let maxLayerSide = 2048

    init(settings: SettingsStore) {
        self.settings = settings
        self.safety = SafetyTolerance.clamp(settings.defaultSafety, for: .flux3Image)
        // Autoguardado: un poco después del último cambio.
        autosave = objectWillChange
            .debounce(for: .seconds(1.2), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveIfNeeded() }
        reloadRecentProjects()
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
            let layer = CollageLayer(sourceURL: url, original: cg, quad: CollageQuad(rect: rect))
            layers.append(layer)
            selectedID = layer.id
        }
    }

    /// Collage nuevo y vacío (el anterior queda guardado en «Collages guardados»).
    func reset() {
        flushSave()
        base = nil
        layers = []
        selectedID = nil
        extraPrompt = ""
        brushMode = nil
        undoStack = []
        redoStack = []
        updateUndoFlags()
        projectURL = nil
        projectName = ""
        projectCreated = Date()
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
        let layer = layers[index]
        let copy = CollageLayer(sourceURL: layer.sourceURL, original: layer.original, mask: layer.mask,
                                quad: layer.quad.translated(by: CGVector(dx: canvasSize.width * 0.03, dy: canvasSize.width * 0.03)),
                                opacity: layer.opacity, isVisible: true, isCutOut: layer.isCutOut)
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
                $0.setOriginal(cut)
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

    /// Lo necesario para aplanar, para poder hacerlo fuera del hilo principal.
    struct FlattenSnapshot: @unchecked Sendable {
        let base: CGImage
        let layers: [(image: CGImage, quad: CollageQuad, opacity: Double)]
    }

    func flattenSnapshot() -> FlattenSnapshot? {
        guard let base else { return nil }
        return FlattenSnapshot(base: base.cgImage, layers: layers.filter { $0.isVisible && $0.opacity > 0 }
            .map { ($0.cgImage, $0.quad, $0.opacity) })
    }

    /// Junta base y capas visibles en una sola imagen del tamaño de la base.
    func flatten() -> CGImage? {
        flattenSnapshot().flatMap { Self.flatten($0) }
    }

    nonisolated static func flatten(_ snapshot: FlattenSnapshot) -> CGImage? {
        let height = CGFloat(snapshot.base.height)
        var result = CIImage(cgImage: snapshot.base)
        let extent = result.extent
        for layer in snapshot.layers {
            // Core Image cuenta la y desde abajo.
            func v(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: height - p.y) }
            guard let filter = CIFilter(name: "CIPerspectiveTransform") else { continue }
            filter.setValue(CIImage(cgImage: layer.image), forKey: kCIInputImageKey)
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

// MARK: - Goma

extension CollageModel {
    /// Empieza un trazo de goma o de recuperar en la capa seleccionada.
    func beginStroke() {
        guard brushMode != nil, let layer = selected else { return }
        let w = layer.original.width, h = layer.original.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        if let mask = layer.mask {
            ctx.draw(mask, in: rect)
        } else {
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.fill(rect)
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        pushUndo()
        stroke = (layer.id, ctx, nil, .distantPast)
    }

    /// Pinta hasta `imagePoint` (en píxeles de la imagen de la capa, y hacia abajo) con radio en píxeles.
    func continueStroke(to imagePoint: CGPoint, radius: CGFloat) {
        guard var current = stroke, let mode = brushMode else { return }
        let ctx = current.context
        // El contexto cuenta la y desde abajo.
        let p = CGPoint(x: imagePoint.x, y: CGFloat(ctx.height) - imagePoint.y)
        let value: CGFloat = mode == .erase ? 0 : 1
        ctx.setStrokeColor(gray: value, alpha: 1)
        ctx.setFillColor(gray: value, alpha: 1)
        if let last = current.last {
            ctx.setLineWidth(radius * 2)
            ctx.move(to: last)
            ctx.addLine(to: p)
            ctx.strokePath()
        } else {
            ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
        current.last = p
        // Vista previa como mucho ~30 veces por segundo.
        if Date().timeIntervalSince(current.lastPreview) > 0.033, let mask = ctx.makeImage(),
           let layer = layers.first(where: { $0.id == current.layerID }),
           let shown = CollageLayer.composite(layer.original, mask: mask) {
            update(current.layerID) { $0.setPreview(shown) }
            current.lastPreview = Date()
        }
        stroke = current
    }

    func endStroke() {
        guard let current = stroke else { return }
        stroke = nil
        let mask = current.context.makeImage()
        update(current.layerID) { $0.setMask(mask) }
    }

    /// Quita todo lo borrado con la goma.
    func clearMask(_ id: UUID) {
        edit(id) { $0.setMask(nil) }
    }
}

// MARK: - Proyectos guardados

/// Collage guardado (para la lista «Abrir»).
struct CollageProjectSummary: Identifiable, Equatable {
    let url: URL
    let name: String
    let modified: Date
    let layerCount: Int
    var id: URL { url }
    var preview: URL { url.appendingPathComponent("vista.jpg") }
}

extension CollageModel {
    var projectsFolder: URL {
        settings.outputFolder.appendingPathComponent("Collages", isDirectory: true)
            .appendingPathComponent("Proyectos", isDirectory: true)
    }

    static func defaultName(_ date: Date = Date()) -> String {
        "Collage " + date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    func rename(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        projectName = clean
        saveIfNeeded(force: true)
    }

    /// Guarda ya lo pendiente (al cambiar de collage o al abrir otro).
    func flushSave() {
        saveIfNeeded()
    }

    /// Guarda el collage en su carpeta si ha cambiado algo desde la última vez.
    func saveIfNeeded(force: Bool = false) {
        guard let base, stroke == nil else { return }
        if projectURL == nil {
            projectCreated = Date()
            if projectName.isEmpty { projectName = Self.defaultName(projectCreated) }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd_HHmmss"
            projectURL = projectsFolder.appendingPathComponent("collage_\(f.string(from: projectCreated))")
                .appendingPathExtension(CollageProjectFile.folderExtension)
        }
        guard let folder = projectURL else { return }

        // Nombre de archivo por imagen: cambia solo si cambia la imagen (así no se reescribe todo).
        var images: [(name: String, image: CGImage)] = []
        let baseName = "base.png"
        images.append((baseName, base.cgImage))
        var fileLayers: [CollageProjectFile.Layer] = []
        for layer in layers {
            let imageName = "capa-\(layer.id.uuidString.prefix(8))-\(layer.originalToken).png"
            images.append((imageName, layer.original))
            var maskName: String?
            if let mask = layer.mask {
                let name = "goma-\(layer.id.uuidString.prefix(8))-\(layer.maskToken).png"
                images.append((name, mask))
                maskName = name
            }
            fileLayers.append(.init(id: layer.id, source: layer.sourceURL.path, imageFile: imageName, maskFile: maskName,
                                    corners: layer.quad.cornerArrays, opacity: layer.opacity,
                                    visible: layer.isVisible, cutOut: layer.isCutOut))
        }
        var file = CollageProjectFile(
            name: projectName, created: projectCreated, modified: Date(), baseFile: baseName,
            baseSource: base.url.path, extraPrompt: extraPrompt, resolution: resolution,
            sendOriginals: sendOriginals, layers: fileLayers
        )
        // Firma sin la fecha: si nada ha cambiado, no se escribe.
        file.modified = .distantPast
        let signature = (try? file.encoded()).map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard force || signature != lastSavedSignature else { return }
        lastSavedSignature = signature
        file.modified = Date()

        let alreadyWritten = savedImages
        let toWrite = images.filter { !alreadyWritten.contains($0.name) }
        let keep = Set(images.map(\.name))
        savedImages = keep
        let snapshot = flattenSnapshot()
        let previous = saveChain
        saveChain = Task.detached(priority: .utility) { [file] in
            await previous?.value
            let preview = snapshot.flatMap { Self.preview(Self.flatten($0)) }
            Self.write(file: file, images: toWrite, keep: keep, preview: preview, to: folder)
        }
        Task { [weak self] in
            await self?.saveChain?.value
            self?.reloadRecentProjects()
        }
    }

    nonisolated private static func write(file: CollageProjectFile, images: [(name: String, image: CGImage)],
                                          keep: Set<String>, preview: CGImage?, to folder: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for item in images {
            writePNG(item.image, to: folder.appendingPathComponent(item.name))
        }
        if let preview { writeJPEG(preview, to: folder.appendingPathComponent("vista.jpg")) }
        if let data = try? file.encoded() {
            try? data.write(to: folder.appendingPathComponent(CollageProjectFile.fileName), options: .atomic)
        }
        // Borra imágenes que ya no usa ninguna capa.
        let existing = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in existing where name.hasSuffix(".png") && !keep.contains(name) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    nonisolated private static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    nonisolated private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    /// Miniatura del collage para la lista de guardados.
    nonisolated private static func preview(_ full: CGImage?) -> CGImage? {
        guard let full else { return nil }
        let maxSide: CGFloat = 480
        let scale = min(1, maxSide / CGFloat(max(full.width, full.height)))
        let w = Int(CGFloat(full.width) * scale), h = Int(CGFloat(full.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    func reloadRecentProjects() {
        let folder = projectsFolder
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        recentProjects = dirs
            .filter { $0.pathExtension == CollageProjectFile.folderExtension }
            .compactMap { dir -> CollageProjectSummary? in
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(CollageProjectFile.fileName)),
                      let file = try? CollageProjectFile.decode(data) else { return nil }
                return CollageProjectSummary(url: dir, name: file.name, modified: file.modified, layerCount: file.layers.count)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// Abre un collage guardado (el actual queda guardado antes).
    func open(_ summary: CollageProjectSummary, state: AppState) {
        flushSave()
        let folder = summary.url
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(CollageProjectFile.fileName)),
              let file = try? CollageProjectFile.decode(data),
              let baseImage = Self.loadImage(folder.appendingPathComponent(file.baseFile)) else {
            state.alert = AppAlert(title: "No se ha podido abrir el collage",
                                   message: "Faltan archivos en «\(summary.name)».")
            return
        }
        var loaded: [CollageLayer] = []
        var missing = 0
        for item in file.layers {
            guard let image = Self.loadImage(folder.appendingPathComponent(item.imageFile)),
                  let quad = item.quad else { missing += 1; continue }
            let mask = item.maskFile.flatMap { Self.loadImage(folder.appendingPathComponent($0), gray: true) }
            loaded.append(CollageLayer(id: item.id, sourceURL: URL(fileURLWithPath: item.source), original: image,
                                       mask: mask, quad: quad, opacity: item.opacity,
                                       isVisible: item.visible, isCutOut: item.cutOut))
        }
        let baseURL = file.baseSource.map { URL(fileURLWithPath: $0) } ?? folder.appendingPathComponent(file.baseFile)
        base = CollageBase(url: baseURL, cgImage: baseImage, image: NSImage(cgImage: baseImage, size: .zero))
        layers = loaded
        selectedID = nil
        brushMode = nil
        extraPrompt = file.extraPrompt
        resolution = file.resolution
        sendOriginals = file.sendOriginals
        undoStack = []
        redoStack = []
        updateUndoFlags()
        projectURL = folder
        projectName = file.name
        projectCreated = file.created
        // Al guardar de nuevo se reescriben las capas con nombres nuevos y se borran los antiguos.
        savedImages = [file.baseFile]
        lastSavedSignature = nil
        if missing > 0 {
            state.alert = AppAlert(title: "Collage abierto con avisos",
                                   message: "No se han podido cargar \(missing) capa(s) de «\(file.name)».")
        }
    }

    func revealProjectInFinder() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    func deleteProject(_ summary: CollageProjectSummary) {
        if summary.url == projectURL { projectURL = nil; lastSavedSignature = nil; savedImages = [] }
        NSWorkspace.shared.recycle([summary.url]) { [weak self] _, _ in
            Task { @MainActor in self?.reloadRecentProjects() }
        }
    }

    private static func loadImage(_ url: URL, gray: Bool = false) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        guard gray else { return image }
        // La máscara tiene que ser gris sin alfa para recortar.
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }
}
