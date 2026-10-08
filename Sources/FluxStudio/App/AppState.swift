import AppKit
import FluxCore
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var opensSettings = false
}

/// Imagen enviada desde el Historial o el feed a otra herramienta.
struct Handoff: Equatable {
    let fileURL: URL
    let mode: AppMode
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
    @Published var handoff: Handoff?

    let settings: SettingsStore
    let history: HistoryStore
    private var tasks: [UUID: [Task<Void, Never>]] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
        self.history = HistoryStore(settings: settings)
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

    /// Ejecuta una petición: enviar → esperar → descargar → guardar.
    private func runSlot<Body: Encodable & Sendable>(
        itemID: UUID, slotID: UUID, index: Int, client: BFLClient,
        endpoint: BFLEndpoint, body: Body, prompt: String, parameters: JSONValue, referenceCount: Int
    ) async {
        do {
            let (submitted, final) = try await client.run(
                endpoint,
                body: body,
                onSubmitted: { [weak self] sub in
                    await self?.didSubmit(itemID: itemID, slotID: slotID, response: sub)
                },
                onUpdate: { [weak self] poll in
                    await self?.setStatus(itemID: itemID, slotID: slotID, status: poll.status)
                }
            )
            guard let result = final.result, let url = result.sampleURLs.first else { throw BFLError.noResult }

            updateSlot(itemID, slotID) { $0.phase = .downloading }
            let download = try await client.download(url)
            let record = GenerationRecord(
                taskID: submitted.id,
                endpoint: endpoint.path,
                model: endpoint.displayName,
                prompt: prompt,
                sentPrompt: prompt,
                expandedPrompt: result.prompt,
                parameters: parameters,
                cost: submitted.cost,
                inputMP: submitted.inputMP,
                outputMP: submitted.outputMP,
                region: settings.region.rawValue,
                referenceCount: referenceCount
            )
            let stored = try ResultStore.save(
                data: download.data, mimeType: download.mimeType, sourceURL: url,
                base: settings.outputFolder, prefix: endpoint.filePrefix, index: index, record: record
            )
            history.add(stored)
            let image = NSImage(data: download.data)
            updateSlot(itemID, slotID) {
                $0.fileURL = stored.fileURL
                $0.image = image
                $0.expandedPrompt = result.prompt
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

    private func didSubmit(itemID: UUID, slotID: UUID, response: SubmitResponse) {
        sessionCredits += response.cost ?? 0
        updateSlot(itemID, slotID) {
            $0.taskID = response.id
            $0.cost = response.cost
            $0.phase = .running(.pending)
        }
    }

    private func setStatus(itemID: UUID, slotID: UUID, status: BFLStatus) {
        updateSlot(itemID, slotID) { $0.phase = .running(status) }
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
        mode = .generate
    }

    func send(_ url: URL, to target: AppMode) {
        handoff = Handoff(fileURL: url, mode: target)
        mode = target
    }

    private func updateSlot(_ itemID: UUID, _ slotID: UUID, _ change: (inout ResultSlot) -> Void) {
        guard let i = feed.firstIndex(where: { $0.id == itemID }),
              let j = feed[i].slots.firstIndex(where: { $0.id == slotID }) else { return }
        change(&feed[i].slots[j])
    }
}
