import AppKit
import FluxCore
import SwiftUI

/// Imagen de entrada de una herramienta. Se muestra al momento y se prepara para enviar
/// (reducir y codificar) solo al generar, no al seleccionarla.
@MainActor
final class ToolImage {
    let url: URL
    let image: NSImage
    /// Tamaño en píxeles de lo que se enviará (puede ser menor que el original).
    let size: CGSize
    private var prepared: ImageEncoder.Encoded?

    private init(url: URL, image: NSImage, size: CGSize) {
        self.url = url
        self.image = image
        self.size = size
    }

    static func load(_ url: URL) async throws -> ToolImage {
        let size = await Task.detached(priority: .userInitiated) { ImageEncoder.uploadSize(fileURL: url) }.value
        guard let size, let image = NSImage(contentsOf: url) else { throw ImageEncoder.EncodeError.unreadable }
        return ToolImage(url: url, image: image, size: CGSize(width: size.width, height: size.height))
    }

    /// Imagen lista para enviar (se calcula la primera vez y se reutiliza).
    func encoded() async throws -> ImageEncoder.Encoded {
        if let prepared { return prepared }
        let url = url
        let encoded = try await Task.detached(priority: .userInitiated) {
            try ImageEncoder.encode(fileURL: url)
        }.value
        prepared = encoded
        return encoded
    }
}

struct ToolResult: Identifiable {
    let id = UUID()
    let url: URL
    let image: NSImage
}

/// Ejecuta una petición de herramienta y guarda sus resultados.
@MainActor
final class ToolRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = ""
    @Published var results: [ToolResult] = []
    @Published var selectedID: UUID?

    private var task: Task<Void, Never>?

    var current: ToolResult? {
        results.first { $0.id == selectedID } ?? results.last
    }

    func run<Body: Encodable & Sendable>(
        state: AppState, endpoint: BFLEndpoint, modelName: String, prompt: String, body: Body,
        referenceCount: Int = 0, source: URL? = nil
    ) {
        run(state: state, endpoint: endpoint, modelName: modelName, prompt: prompt,
            referenceCount: referenceCount, source: source) { body }
    }

    /// Igual, pero el cuerpo se prepara al lanzar (p. ej. codificar la imagen de entrada).
    func run<Body: Encodable & Sendable>(
        state: AppState, endpoint: BFLEndpoint, modelName: String, prompt: String,
        referenceCount: Int = 0, source: URL? = nil,
        prepare: @escaping @MainActor () async throws -> Body
    ) {
        guard !isRunning else { return }
        let client: BFLClient
        do {
            client = try state.settings.makeClient()
        } catch {
            state.alert = AppAlert(title: "Falta la API key", message: error.localizedDescription, opensSettings: true)
            return
        }
        isRunning = true
        status = "Preparando imagen"
        task = Task { [weak self] in
            do {
                let body = try await prepare()
                try Task.checkCancellation()
                let parameters = (try? JSONValue(encoding: body))?.strippingLargeStrings() ?? .null
                self?.status = "Enviando"
                let output = try await state.runJob(
                    client: client, endpoint: endpoint, body: body, modelName: modelName,
                    prefix: endpoint.filePrefix, index: 0, prompt: prompt, sentPrompt: prompt,
                    parameters: parameters, referenceCount: referenceCount, source: source
                ) { [weak self] phase, _, _ in
                    self?.status = PreciseEditModel.describe(phase)
                }
                if let image = NSImage(data: output.data) {
                    let result = ToolResult(url: output.stored.fileURL, image: image)
                    self?.results.append(result)
                    self?.selectedID = result.id
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch {
                state.alert = AppAlert(title: "No se ha podido completar", message: error.localizedDescription)
            }
            self?.isRunning = false
            self?.status = ""
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    func clear() {
        cancel()
        results = []
        selectedID = nil
    }
}

/// Base común: imagen de entrada, tolerancia, formato, semilla y ejecución.
@MainActor
class BaseToolModel: ObservableObject {
    @Published var input: ToolImage?
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var safety: Int
    @Published var format: ToolOutputFormat = .jpeg
    @Published var seedText = ""
    let runner = ToolRunner()
    let endpoint: BFLEndpoint

    init(endpoint: BFLEndpoint, settings: SettingsStore) {
        self.endpoint = endpoint
        self.safety = SafetyTolerance.clamp(settings.defaultSafety, for: endpoint)
        self.format = ToolOutputFormat(rawValue: settings.defaultFormat.rawValue) ?? .jpeg
    }

    var seed: Int? { Int(seedText.trimmingCharacters(in: .whitespaces)) }

    func load(_ url: URL) {
        isLoading = true
        Task {
            do {
                input = try await ToolImage.load(url)
                loadError = nil
                didLoadInput()
            } catch {
                loadError = "«\(url.lastPathComponent)»: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    /// Para que cada herramienta reinicie su estado al cambiar de imagen.
    func didLoadInput() {}

    func reset() {
        runner.clear()
        input = nil
        loadError = nil
    }

    /// Carga la imagen seleccionada en el Estudio si no es ya la de entrada.
    func sync(with url: URL?) {
        guard let url, input?.url != url, !isLoading else { return }
        load(url)
    }
}

// MARK: - Ampliar

@MainActor
final class OutpaintModel: BaseToolModel {
    struct Preset: Hashable {
        let label: String
        let ratio: Double?
    }

    static let presets: [Preset] = [
        Preset(label: "Original", ratio: nil), Preset(label: "1:1", ratio: 1), Preset(label: "4:5", ratio: 0.8),
        Preset(label: "3:4", ratio: 0.75), Preset(label: "2:3", ratio: 2.0 / 3.0), Preset(label: "9:16", ratio: 9.0 / 16.0),
        Preset(label: "16:9", ratio: 16.0 / 9.0), Preset(label: "3:2", ratio: 1.5), Preset(label: "4:3", ratio: 4.0 / 3.0),
        Preset(label: "21:9", ratio: 21.0 / 9.0),
    ]
    static let expansions: [Double] = [1, 1.25, 1.5, 2]

    @Published var preset = OutpaintModel.presets[0] { didSet { applyPreset() } }
    @Published var expand = 1.5 { didSet { applyPreset() } }
    @Published var canvasSize = CGSize(width: 1024, height: 1024)
    /// Esquina superior izquierda de la imagen dentro del lienzo; nil = centrada.
    @Published var offset: CGPoint?
    @Published var prompt = ""
    @Published var mode: OutpaintRequest.Mode = .high
    @Published var autoCrop = false
    @Published var disablePup = false

    init(settings: SettingsStore) {
        super.init(endpoint: .outpaint, settings: settings)
    }

    override func didLoadInput() {
        applyPreset()
    }

    func applyPreset() {
        guard let input else { return }
        canvasSize = OutpaintGeometry.canvas(for: input.size, ratio: preset.ratio, expand: expand)
        offset = nil
    }

    func setCanvas(width: Int? = nil, height: Int? = nil) {
        guard let input else { return }
        canvasSize = CGSize(
            width: max(Double(width ?? Int(canvasSize.width)), input.size.width, 64),
            height: max(Double(height ?? Int(canvasSize.height)), input.size.height, 64)
        )
        if let offset { self.offset = OutpaintGeometry.clamp(offset, source: input.size, canvas: canvasSize) }
    }

    var effectiveOffset: CGPoint {
        guard let input else { return .zero }
        return offset ?? OutpaintGeometry.centeredOffset(source: input.size, canvas: canvasSize)
    }

    var canGenerate: Bool {
        guard let input else { return false }
        return canvasSize.width > input.size.width || canvasSize.height > input.size.height
    }

    func generate(state: AppState) {
        guard let input else { return }
        let canvas = canvasSize, offset = offset
        let prompt = prompt, autoCrop = autoCrop, mode = mode, disablePup = disablePup
        let safety = safety, format = format
        let description = prompt.isEmpty ? "Ampliar \(Int(canvas.width))×\(Int(canvas.height))" : prompt
        runner.run(state: state, endpoint: .outpaint, modelName: "Ampliar", prompt: description, source: input.url) {
            let encoded = try await input.encoded()
            // El tamaño real puede diferir en 1 px del calculado: el lienzo nunca es menor que la imagen.
            let source = CGSize(width: encoded.pixelWidth, height: encoded.pixelHeight)
            let width = max(Int(canvas.width), encoded.pixelWidth)
            let height = max(Int(canvas.height), encoded.pixelHeight)
            let fitted = offset.map {
                OutpaintGeometry.clamp($0, source: source, canvas: CGSize(width: width, height: height))
            }
            return OutpaintRequest(
                inputImage: encoded.base64, width: width, height: height,
                prompt: prompt, offset: fitted, autoCrop: autoCrop, mode: mode, disablePup: disablePup,
                safetyTolerance: safety, outputFormat: format
            )
        }
    }
}

// MARK: - Borrar

@MainActor
final class EraseModel: BaseToolModel {
    @Published var strokes: [MaskStroke] = []
    @Published var redoStack: [MaskStroke] = []
    @Published var inverted = false
    @Published var isEraser = false
    /// Radio del pincel como fracción del ancho de la imagen.
    @Published var brushRadius = 0.03
    @Published var dilatePixels = 10.0

    init(settings: SettingsStore) {
        super.init(endpoint: .erase, settings: settings)
    }

    override func didLoadInput() {
        clearMask()
    }

    func add(_ stroke: MaskStroke) {
        strokes.append(stroke)
        redoStack.removeAll()
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        redoStack.append(last)
    }

    func redo() {
        guard let last = redoStack.popLast() else { return }
        strokes.append(last)
    }

    func clearMask() {
        strokes = []
        redoStack = []
        inverted = false
        isEraser = false
    }

    var maskIsEmpty: Bool { MaskRenderer.isEmpty(strokes: strokes, inverted: inverted) }

    struct MaskError: LocalizedError {
        var errorDescription: String? { "No se ha podido crear la máscara." }
    }

    func generate(state: AppState) {
        guard let input, !maskIsEmpty else { return }
        let strokes = strokes, inverted = inverted, dilate = Int(dilatePixels)
        let seed = seed, safety = safety, format = format
        runner.run(state: state, endpoint: .erase, modelName: "Borrar", prompt: "Borrar zona pintada", source: input.url) {
            let encoded = try await input.encoded()
            // La máscara se genera al tamaño exacto de la imagen que se envía.
            guard let mask = MaskRenderer.pngData(
                strokes: strokes, inverted: inverted,
                width: encoded.pixelWidth, height: encoded.pixelHeight
            ) else { throw MaskError() }
            return EraseRequest(
                image: encoded.base64, mask: mask.base64EncodedString(),
                dilatePixels: dilate, seed: seed, safetyTolerance: safety, outputFormat: format
            )
        }
    }
}

// MARK: - Deblur

@MainActor
final class DeblurModel: BaseToolModel {
    init(settings: SettingsStore) {
        super.init(endpoint: .deblur, settings: settings)
    }

    func generate(state: AppState) {
        guard let input else { return }
        let seed = seed, safety = safety, format = format
        runner.run(state: state, endpoint: .deblur, modelName: "Deblur", prompt: "Quitar desenfoque", source: input.url) {
            let encoded = try await input.encoded()
            return DeblurRequest(image: encoded.base64, seed: seed, safetyTolerance: safety, outputFormat: format)
        }
    }
}

// MARK: - Probador

@MainActor
final class TryOnModel: BaseToolModel {
    @Published var garment: ToolImage?
    @Published var garmentLoading = false
    @Published var garmentDescription = ""
    @Published var customPrompt: String?

    init(settings: SettingsStore) {
        super.init(endpoint: .vto, settings: settings)
    }

    func loadGarment(_ url: URL) {
        garmentLoading = true
        Task {
            do {
                garment = try await ToolImage.load(url)
            } catch {
                loadError = "«\(url.lastPathComponent)»: \(error.localizedDescription)"
            }
            garmentLoading = false
        }
    }

    var prompt: String {
        customPrompt ?? TryOnRequest.prompt(forGarment: garmentDescription)
    }

    override func reset() {
        super.reset()
        garment = nil
    }

    func generate(state: AppState) {
        guard let input, let garment else { return }
        let prompt = prompt, seed = seed, safety = safety, format = format
        runner.run(state: state, endpoint: .vto, modelName: "Probador", prompt: prompt,
                   referenceCount: 1, source: input.url) {
            let person = try await input.encoded()
            let clothing = try await garment.encoded()
            return TryOnRequest(prompt: prompt, person: person.base64, garment: clothing.base64,
                                seed: seed, safetyTolerance: safety, outputFormat: format)
        }
    }
}
