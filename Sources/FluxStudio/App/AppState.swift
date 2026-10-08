import AppKit
import FluxCore
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var opensSettings = false
}

/// Herramientas del Estudio: todas trabajan sobre la imagen seleccionada.
enum WorkspaceTool: String, CaseIterable, Identifiable {
    case generate, edit, erase, outpaint, deblur, tryOn, video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: return "Generar"
        case .edit: return "Editar"
        case .erase: return "Borrar"
        case .outpaint: return "Ampliar"
        case .deblur: return "Deblur"
        case .tryOn: return "Probador"
        case .video: return "Vídeo"
        }
    }

    var icon: String {
        switch self {
        case .generate: return "sparkles"
        case .edit: return "selection.pin.in.out"
        case .erase: return "eraser"
        case .outpaint: return "arrow.up.left.and.arrow.down.right"
        case .deblur: return "camera.aperture"
        case .tryOn: return "tshirt"
        case .video: return "film"
        }
    }

    var help: String {
        switch self {
        case .generate: return "Generar imágenes nuevas con FLUX 3 Image"
        case .edit: return "Editar con precisión: regiones con instrucciones"
        case .erase: return "Borrar objetos pintando encima"
        case .outpaint: return "Ampliar la imagen más allá de sus bordes (Outpainting)"
        case .deblur: return "Quitar el desenfoque"
        case .tryOn: return "Probador virtual: vestir a la persona con una prenda"
        case .video: return "Crear un vídeo a partir de la imagen"
        }
    }

    /// Las herramientas de edición necesitan una imagen seleccionada.
    var needsImage: Bool { self != .generate && self != .video }
}

/// Petición en curso (se muestra en la tira de resultados).
struct ActiveJob: Identifiable, Equatable {
    let id = UUID()
    let label: String
    var status: String
}

/// Estado principal de la app: modo activo, feed y generaciones en curso.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .generate
    @Published var feed: [FeedItem] = []
    @Published var prompt = ""
    @Published var imageParams = ImageParams()
    @Published var references: [ReferenceImage] = []
    @Published var sessionCredits: Double = 0
    @Published var alert: AppAlert?
    /// Imagen seleccionada en el Estudio (todas las herramientas trabajan sobre ella).
    @Published var focusedURL: URL?
    @Published var tool: WorkspaceTool = .generate
    @Published var activeJobs: [ActiveJob] = []
    /// De qué imagen sale cada resultado (para Antes / Después).
    @Published private(set) var parents: [URL: URL] = [:]

    let settings: SettingsStore
    let history: HistoryStore
    let preciseEdit: PreciseEditModel
    let outpaint: OutpaintModel
    let erase: EraseModel
    let deblur: DeblurModel
    let tryOn: TryOnModel
    let video: VideoModel
    private var tasks: [UUID: [Task<Void, Never>]] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
        self.history = HistoryStore(settings: settings)
        self.preciseEdit = PreciseEditModel()
        self.outpaint = OutpaintModel(settings: settings)
        self.erase = EraseModel(settings: settings)
        self.deblur = DeblurModel(settings: settings)
        self.tryOn = TryOnModel(settings: settings)
        self.video = VideoModel(settings: settings)
        imageParams.count = settings.defaultImageCount
        imageParams.safety = SafetyTolerance.clamp(settings.defaultSafety, for: .flux3Image)
    }

    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !references.contains(where: \.isProcessing)
    }

    // MARK: - Referencias

    func addReferences(_ urls: [URL]) {
        let images = urls.filter(ReferenceImage.isSupported)
        guard !images.isEmpty else {
            alert = AppAlert(title: "Archivo no compatible", message: "Solo se pueden añadir imágenes (JPEG, PNG, WebP, HEIC…).")
            return
        }
        let free = Flux3Image.maxReferenceImages - references.count
        guard free > 0 else {
            alert = AppAlert(title: "Máximo de referencias", message: "FLUX 3 Image admite hasta \(Flux3Image.maxReferenceImages) imágenes de referencia. Quita alguna para añadir otra.")
            return
        }
        if images.count > free {
            alert = AppAlert(title: "Máximo de referencias", message: "Solo caben \(Flux3Image.maxReferenceImages) referencias: se han añadido las \(free) primeras.")
        }
        for url in images.prefix(free) {
            let reference = ReferenceImage(sourceURL: url)
            references.append(reference)
            prepare(reference)
        }
    }

    private func prepare(_ reference: ReferenceImage) {
        let id = reference.id
        let url = reference.sourceURL
        Task { [weak self] in
            async let thumb = ThumbnailLoader.load(url, maxPixelSize: 200)
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImageEncoder.Encoded, Error> in
                Result { try ImageEncoder.encode(fileURL: url) }
            }.value
            let thumbnail = await thumb
            self?.updateReference(id) {
                $0.thumbnail = thumbnail
                switch result {
                case .success(let encoded): $0.encoded = encoded
                case .failure(let error): $0.error = error.localizedDescription
                }
            }
        }
    }

    func removeReference(_ id: UUID) {
        references.removeAll { $0.id == id }
    }

    func moveReference(_ id: UUID, by offset: Int) {
        guard let i = references.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard references.indices.contains(j) else { return }
        references.swapAt(i, j)
    }

    func clearReferences() {
        references.removeAll()
    }

    private func updateReference(_ id: UUID, _ change: (inout ReferenceImage) -> Void) {
        guard let i = references.firstIndex(where: { $0.id == id }) else { return }
        change(&references[i])
    }

    // MARK: - Generar con FLUX 3 Image

    func generateImage() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let failed = references.first(where: { $0.error != nil }) {
            alert = AppAlert(title: "Referencia no válida", message: "«\(failed.sourceURL.lastPathComponent)»: \(failed.error ?? ""). Quítala para continuar.")
            return
        }
        guard !references.contains(where: \.isProcessing) else { return }
        let client: BFLClient
        do {
            client = try settings.makeClient()
        } catch {
            alert = AppAlert(title: "Falta la API key", message: error.localizedDescription, opensSettings: true)
            return
        }

        let p = imageParams
        let encoded = references.compactMap(\.encoded)
        let body = Flux3ImageRequest(
            prompt: text,
            images: encoded.map(\.base64),
            aspectRatio: p.aspectRatio,
            resolution: p.resolution,
            safetyTolerance: p.safety,
            grounding: p.grounding
        )
        // Con "auto" y referencias, la primera imagen fija la proporción.
        let aspect = AspectRatio.value(of: p.aspectRatio) ?? encoded.first?.aspectRatio ?? 1
        let item = FeedItem(
            prompt: text,
            modelName: BFLEndpoint.flux3Image.displayName,
            aspectRatio: aspect,
            referenceThumbnails: references.compactMap(\.thumbnail),
            slots: (0..<max(1, min(4, p.count))).map { _ in ResultSlot() }
        )
        feed.append(item)
        prompt = ""

        let parameters = (try? JSONValue(encoding: body))?.strippingLargeStrings() ?? .null
        let referenceCount = encoded.count
        tasks[item.id] = item.slots.enumerated().map { index, slot in
            Task { [weak self] in
                await self?.runSlot(
                    itemID: item.id, slotID: slot.id, index: index, client: client,
                    endpoint: .flux3Image, body: body, prompt: text,
                    parameters: parameters, referenceCount: referenceCount
                )
            }
        }
    }

    /// Ejecuta una petición del feed y refleja su estado en el hueco correspondiente.
    private func runSlot<Body: Encodable & Sendable>(
        itemID: UUID, slotID: UUID, index: Int, client: BFLClient,
        endpoint: BFLEndpoint, body: Body, prompt: String, parameters: JSONValue, referenceCount: Int
    ) async {
        do {
            let output = try await runJob(
                client: client, endpoint: endpoint, body: body, modelName: endpoint.displayName,
                prefix: endpoint.filePrefix, index: index, prompt: prompt, sentPrompt: prompt,
                parameters: parameters, referenceCount: referenceCount
            ) { [weak self] phase, taskID, cost in
                self?.updateSlot(itemID, slotID) {
                    $0.phase = phase
                    if let taskID { $0.taskID = taskID }
                    if let cost { $0.cost = cost }
                }
            }
            updateSlot(itemID, slotID) {
                $0.fileURL = output.stored.fileURL
                $0.image = NSImage(data: output.data)
                $0.expandedPrompt = output.result.prompt
                $0.phase = .done
            }
        } catch is CancellationError {
            updateSlot(itemID, slotID) { $0.phase = .cancelled }
        } catch let error as URLError where error.code == .cancelled {
            updateSlot(itemID, slotID) { $0.phase = .cancelled }
        } catch {
            updateSlot(itemID, slotID) { $0.phase = .failed(error.localizedDescription) }
        }
    }

    struct JobOutput {
        let stored: StoredResult
        let data: Data
        let result: PollResult
        let submitted: SubmitResponse
    }

    typealias JobProgress = @MainActor @Sendable (ResultSlot.Phase, _ taskID: String?, _ cost: Double?) -> Void

    /// Mecanismo común: enviar → esperar → descargar → guardar en disco y en el Historial.
    func runJob<Body: Encodable & Sendable>(
        client: BFLClient, endpoint: BFLEndpoint, body: Body, modelName: String, prefix: String,
        index: Int, prompt: String, sentPrompt: String, parameters: JSONValue, referenceCount: Int,
        source: URL? = nil,
        progress: @escaping JobProgress
    ) async throws -> JobOutput {
        let job = ActiveJob(label: modelName, status: "Enviando")
        activeJobs.insert(job, at: 0)
        defer { activeJobs.removeAll { $0.id == job.id } }
        let jobID = job.id

        let (submitted, final) = try await client.run(
            endpoint,
            body: body,
            onSubmitted: { [weak self] sub in
                await self?.addCredits(sub.cost)
                await self?.setJobStatus(jobID, .running(.pending))
                await progress(.running(.pending), sub.id, sub.cost)
            },
            onUpdate: { [weak self] poll in
                await self?.setJobStatus(jobID, .running(poll.status))
                await progress(.running(poll.status), nil, nil)
            }
        )
        guard let result = final.result, let url = result.sampleURLs.first else { throw BFLError.noResult }
        setJobStatus(jobID, .downloading)
        progress(.downloading, nil, nil)
        let download = try await client.download(url)
        let record = GenerationRecord(
            taskID: submitted.id,
            endpoint: endpoint.path,
            model: modelName,
            prompt: prompt,
            sentPrompt: sentPrompt,
            expandedPrompt: result.prompt,
            parameters: parameters,
            cost: submitted.cost,
            inputMP: submitted.inputMP,
            outputMP: submitted.outputMP,
            region: settings.region.rawValue,
            referenceCount: referenceCount,
            draftCaches: result.draftCaches.isEmpty ? nil : result.draftCaches
        )
        let stored = try ResultStore.save(
            data: download.data, mimeType: download.mimeType, sourceURL: url,
            base: settings.outputFolder, prefix: prefix, index: index, record: record
        )
        history.add(stored)
        if let source { parents[stored.fileURL] = source }
        // El resultado nuevo pasa a ser la imagen seleccionada: se puede seguir editando.
        focusedURL = stored.fileURL
        return JobOutput(stored: stored, data: download.data, result: result, submitted: submitted)
    }

    private func setJobStatus(_ id: UUID, _ phase: ResultSlot.Phase) {
        guard let i = activeJobs.firstIndex(where: { $0.id == id }) else { return }
        activeJobs[i].status = PreciseEditModel.describe(phase)
    }

    private func addCredits(_ cost: Double?) {
        sessionCredits += cost ?? 0
    }

    func cancel(itemID: UUID) {
        tasks[itemID]?.forEach { $0.cancel() }
        tasks[itemID] = nil
    }

    func remove(itemID: UUID) {
        cancel(itemID: itemID)
        feed.removeAll { $0.id == itemID }
    }

    // MARK: - Reutilizar y enviar a otras herramientas

    /// Vuelve a poner el prompt de una fila del feed en la barra.
    func reuse(_ item: FeedItem) {
        prompt = item.prompt
        tool = .generate
        mode = .generate
    }

    /// Recupera prompt y parámetros de un resultado guardado.
    func reuse(_ record: GenerationRecord) {
        prompt = record.prompt
        if record.endpoint == BFLEndpoint.flux3Image.path {
            let s = Flux3ImageSettings(parameters: record.parameters)
            imageParams.aspectRatio = s.aspectRatio
            imageParams.resolution = s.resolution
            imageParams.safety = s.safetyTolerance
            imageParams.grounding = s.grounding
        }
        tool = .generate
        mode = .generate
        if (record.referenceCount ?? 0) > 0 {
            alert = AppAlert(
                title: "Parámetros recuperados",
                message: "Esta imagen usó \(record.referenceCount ?? 0) referencia(s). Las referencias no se guardan: vuelve a añadirlas si las necesitas."
            )
        }
    }

    func useAsReference(_ url: URL) {
        addReferences([url])
        tool = .generate
        mode = .generate
    }

    /// Selecciona una imagen en el Estudio (y opcionalmente una herramienta).
    func focus(_ url: URL, tool: WorkspaceTool? = nil) {
        focusedURL = url
        if let tool { self.tool = tool }
        mode = .generate
    }

    func send(_ url: URL, to target: AppMode) {
        let tool: WorkspaceTool
        switch target {
        case .preciseEdit: tool = .edit
        case .outpaint: tool = .outpaint
        case .erase: tool = .erase
        case .deblur: tool = .deblur
        case .tryOn: tool = .tryOn
        case .video: tool = .video
        default: tool = .generate
        }
        if target == .video {
            if VideoModel.isVideo(url) {
                video.mode = .v2v
            } else {
                video.mode = .i2v
                if video.keyframes.isEmpty { video.addKeyframes([url]) }
            }
        }
        focus(url, tool: tool)
    }

    func parent(of url: URL?) -> URL? {
        url.flatMap { parents[$0] }
    }

    var isGenerating: Bool {
        feed.contains { $0.isRunning }
    }

    func cancelAllGenerations() {
        for item in feed where item.isRunning { cancel(itemID: item.id) }
    }

    private func updateSlot(_ itemID: UUID, _ slotID: UUID, _ change: (inout ResultSlot) -> Void) {
        guard let i = feed.firstIndex(where: { $0.id == itemID }),
              let j = feed[i].slots.firstIndex(where: { $0.id == slotID }) else { return }
        change(&feed[i].slots[j])
    }
}
