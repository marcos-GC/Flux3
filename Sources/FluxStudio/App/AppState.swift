import AppKit
import FluxCore
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var opensSettings = false
}

/// Estado principal de la app: modo activo, feed y generaciones en curso.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: AppMode = .generate
    @Published var feed: [FeedItem] = []
    @Published var prompt = ""
    @Published var imageParams = ImageParams()
    @Published var sessionCredits: Double = 0
    @Published var alert: AppAlert?

    let settings: SettingsStore
    private var tasks: [UUID: [Task<Void, Never>]] = [:]

    init(settings: SettingsStore) {
        self.settings = settings
        imageParams.count = settings.defaultImageCount
        imageParams.safety = SafetyTolerance.clamp(settings.defaultSafety, for: .flux3Image)
    }

    var canGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Generar con FLUX 3 Image

    func generateImage() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let client: BFLClient
        do {
            client = try settings.makeClient()
        } catch {
            alert = AppAlert(title: "Falta la API key", message: error.localizedDescription, opensSettings: true)
            return
        }

        let p = imageParams
        let body = Flux3ImageRequest(
            prompt: text,
            aspectRatio: p.aspectRatio,
            resolution: p.resolution,
            safetyTolerance: p.safety,
            grounding: p.grounding
        )
        let item = FeedItem(
            prompt: text,
            modelName: BFLEndpoint.flux3Image.displayName,
            aspectRatio: AspectRatio.value(of: p.aspectRatio) ?? 1,
            slots: (0..<max(1, min(4, p.count))).map { _ in ResultSlot() }
        )
        feed.append(item)
        prompt = ""

        let parameters = (try? JSONValue(encoding: body))?.strippingLargeStrings() ?? .null
        tasks[item.id] = item.slots.enumerated().map { index, slot in
            Task { [weak self] in
                await self?.runSlot(
                    itemID: item.id, slotID: slot.id, index: index, client: client,
                    endpoint: .flux3Image, body: body, prompt: text, parameters: parameters
                )
            }
        }
    }

    /// Ejecuta una petición: enviar → esperar → descargar → guardar.
    private func runSlot<Body: Encodable & Sendable>(
        itemID: UUID, slotID: UUID, index: Int, client: BFLClient,
        endpoint: BFLEndpoint, body: Body, prompt: String, parameters: JSONValue
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
                createdAt: Date(),
                prompt: prompt,
                sentPrompt: prompt,
                expandedPrompt: result.prompt,
                parameters: parameters,
                cost: submitted.cost,
                inputMP: submitted.inputMP,
                outputMP: submitted.outputMP,
                region: settings.region.rawValue,
                file: ""
            )
            let fileURL = try ResultStore.save(
                data: download.data, mimeType: download.mimeType, sourceURL: url,
                base: settings.outputFolder, prefix: endpoint.filePrefix, index: index, record: record
            )
            let image = NSImage(data: download.data)
            updateSlot(itemID, slotID) {
                $0.fileURL = fileURL
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

    /// Vuelve a poner el prompt y los parámetros de una fila en la barra.
    func reuse(_ item: FeedItem) {
        prompt = item.prompt
        mode = .generate
    }

    private func updateSlot(_ itemID: UUID, _ slotID: UUID, _ change: (inout ResultSlot) -> Void) {
        guard let i = feed.firstIndex(where: { $0.id == itemID }),
              let j = feed[i].slots.firstIndex(where: { $0.id == slotID }) else { return }
        change(&feed[i].slots[j])
    }
}
