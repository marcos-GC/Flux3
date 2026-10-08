import AppKit
import FluxCore
import SwiftUI

/// Imagen de entrada de una herramienta, ya preparada para enviar.
struct ToolImage {
    let url: URL
    let image: NSImage
    let encoded: ImageEncoder.Encoded

    /// Tamaño en píxeles de lo que se envía (puede ser menor que el original).
    var size: CGSize { CGSize(width: encoded.pixelWidth, height: encoded.pixelHeight) }

    static func load(_ url: URL) async throws -> ToolImage {
        let encoded = try await Task.detached(priority: .userInitiated) {
            try ImageEncoder.encode(fileURL: url)
        }.value
        guard let image = NSImage(contentsOf: url) else { throw ImageEncoder.EncodeError.unreadable }
        return ToolImage(url: url, image: image, encoded: encoded)
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
        state: AppState, endpoint: BFLEndpoint, modelName: String, prompt: String, body: Body, referenceCount: Int = 0
    ) {
        guard !isRunning else { return }
        let client: BFLClient
        do {
            client = try state.settings.makeClient()
        } catch {
            state.alert = AppAlert(title: "Falta la API key", message: error.localizedDescription, opensSettings: true)
            return
        }
        let parameters = (try? JSONValue(encoding: body))?.strippingLargeStrings() ?? .null
        isRunning = true
        status = "Enviando"
        task = Task { [weak self] in
            do {
                let output = try await state.runJob(
                    client: client, endpoint: endpoint, body: body, modelName: modelName,
                    prefix: endpoint.filePrefix, index: 0, prompt: prompt, sentPrompt: prompt,
                    parameters: parameters, referenceCount: referenceCount
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

    /// Usa el resultado mostrado como nueva imagen de entrada (para encadenar ediciones).
    func useCurrentResultAsInput() {
        guard let url = runner.current?.url else { return }
        load(url)
    }
}

// MARK: - Outpainting

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
        let body = OutpaintRequest(
            inputImage: input.encoded.base64, width: Int(canvasSize.width), height: Int(canvasSize.height),
            prompt: prompt, offset: offset, autoCrop: autoCrop, mode: mode, disablePup: disablePup,
            safetyTolerance: safety, outputFormat: format
        )
        let description = prompt.isEmpty ? "Outpainting \(Int(canvasSize.width))×\(Int(canvasSize.height))" : prompt
        runner.run(state: state, endpoint: .outpaint, modelName: "Outpainting", prompt: description, body: body)
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
    }

    var maskIsEmpty: Bool { MaskRenderer.isEmpty(strokes: strokes, inverted: inverted) }

    func generate(state: AppState) {
        guard let input, !maskIsEmpty else { return }
        // La máscara se genera al tamaño exacto de la imagen que se envía.
        guard let mask = MaskRenderer.pngData(
            strokes: strokes, inverted: inverted,
            width: input.encoded.pixelWidth, height: input.encoded.pixelHeight
        ) else {
            state.alert = AppAlert(title: "Máscara no válida", message: "No se ha podido crear la máscara.")
            return
        }
        let body = EraseRequest(
            image: input.encoded.base64, mask: mask.base64EncodedString(),
            dilatePixels: Int(dilatePixels), seed: seed, safetyTolerance: safety, outputFormat: format
        )
        runner.run(state: state, endpoint: .erase, modelName: "Borrar", prompt: "Borrar zona pintada", body: body)
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
        let body = DeblurRequest(image: input.encoded.base64, seed: seed, safetyTolerance: safety, outputFormat: format)
        runner.run(state: state, endpoint: .deblur, modelName: "Deblur", prompt: "Quitar desenfoque", body: body)
    }
}

// MARK: - Probador virtual

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
        let body = TryOnRequest(prompt: prompt, person: input.encoded.base64, garment: garment.encoded.base64,
                                seed: seed, safetyTolerance: safety, outputFormat: format)
        runner.run(state: state, endpoint: .vto, modelName: "Probador virtual", prompt: prompt, body: body, referenceCount: 1)
    }
}
