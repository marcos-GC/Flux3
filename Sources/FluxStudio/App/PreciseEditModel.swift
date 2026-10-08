import AppKit
import FluxCore
import SwiftUI

/// Una versión de la imagen en edición (la original o un resultado).
struct EditVersion: Identifiable {
    let id = UUID()
    let fileURL: URL
    let image: NSImage
    let pixelSize: CGSize
    /// Versión de la que sale (para el comparador Antes/Después).
    let parentIndex: Int?
}

/// Imagen de referencia de una región o global.
struct EditReference: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var thumbnail: NSImage?
    var encoded: ImageEncoder.Encoded?
    var error: String?

    var isProcessing: Bool { encoded == nil && error == nil }
}

/// Región dibujada. Las cajas se guardan normalizadas (0–1) para que sigan valiendo
/// aunque la siguiente versión tenga otro tamaño en píxeles.
struct RegionDraft: Identifiable, Equatable {
    let id = UUID()
    var kind: RegionKind = .edit
    /// Caja principal: origen (Editar, Mover, Ancla) o destino (Nuevo).
    var rect: CGRect
    /// Caja destino en el modo Mover.
    var target: CGRect?
    var instruction = ""
    var reference: EditReference?

    var displayText: String {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .anchor: return text.isEmpty ? "No cambiar" : text
        case .move: return text.isEmpty ? "Mover" : text
        default: return text.isEmpty ? "Sin instrucción" : text
        }
    }
}

/// Estado de "Editar con precisión" (se conserva al cambiar de modo).
@MainActor
final class PreciseEditModel: ObservableObject {
    @Published var versions: [EditVersion] = []
    @Published var currentIndex = 0
    @Published var regions: [RegionDraft] = []
    @Published var selectedRegionID: UUID?
    @Published var globalInstruction = ""
    @Published var extraReferences: [EditReference] = []
    @Published var showRegions = true
    @Published var compareMode = false
    @Published var manualPrompt: String?
    @Published var resolution = "1k"
    @Published var count = 1
    @Published var safety = SafetyTolerance.defaultValue
    @Published var grounding = true
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    @Published private(set) var isGenerating = false
    @Published private(set) var statusText = ""
    @Published var loadError: String?

    /// Estado de interacción que no necesita redibujar la vista.
    var spaceHeld = false
    var pointerInCanvas = false

    private var generationTask: Task<Void, Never>?

    var current: EditVersion? {
        versions.indices.contains(currentIndex) ? versions[currentIndex] : nil
    }

    var parentOfCurrent: EditVersion? {
        guard let p = current?.parentIndex, versions.indices.contains(p) else { return nil }
        return versions[p]
    }

    // MARK: - Imagen

    func load(_ url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            loadError = "No se puede abrir «\(url.lastPathComponent)»."
            return
        }
        let size = ImageEncoder.pixelSize(fileURL: url).map { CGSize(width: $0.width, height: $0.height) } ?? image.size
        reset()
        versions = [EditVersion(fileURL: url, image: image, pixelSize: size, parentIndex: nil)]
        currentIndex = 0
        resolution = Self.suggestedResolution(for: size)
        loadError = nil
    }

    func reset() {
        generationTask?.cancel()
        versions = []
        currentIndex = 0
        regions = []
        selectedRegionID = nil
        globalInstruction = ""
        extraReferences = []
        manualPrompt = nil
        compareMode = false
        zoom = 1
        pan = .zero
        isGenerating = false
        statusText = ""
    }

    /// Resolución de salida más parecida a la de la imagen original.
    static func suggestedResolution(for size: CGSize) -> String {
        let mp = size.width * size.height / 1_000_000
        switch mp {
        case ..<1.3: return "1k"
        case ..<3: return "1.5k"
        case ..<7: return "2k"
        default: return "4k"
        }
    }

    func goToVersion(_ index: Int) {
        guard versions.indices.contains(index) else { return }
        currentIndex = index
        if current?.parentIndex == nil { compareMode = false }
    }

    // MARK: - Regiones

    func addRegion(_ rect: CGRect) {
        let region = RegionDraft(rect: rect.clampedToUnit)
        regions.append(region)
        selectedRegionID = region.id
    }

    func addDefaultRegion() {
        let offset = CGFloat(regions.count % 5) * 0.04
        addRegion(CGRect(x: 0.35 + offset, y: 0.35 + offset, width: 0.3, height: 0.3))
    }

    func clearRegions() {
        regions.removeAll()
        selectedRegionID = nil
    }

    func removeRegion(_ id: UUID) {
        regions.removeAll { $0.id == id }
        if selectedRegionID == id { selectedRegionID = nil }
    }

    func update(_ id: UUID, _ change: (inout RegionDraft) -> Void) {
        guard let i = regions.firstIndex(where: { $0.id == id }) else { return }
        change(&regions[i])
    }

    func setKind(_ kind: RegionKind, for id: UUID) {
        update(id) { region in
            region.kind = kind
            if kind == .move && region.target == nil {
                var t = region.rect
                t.origin.x = min(1 - t.width, t.origin.x + max(0.1, t.width * 0.6))
                region.target = t.clampedToUnit
            }
            if kind != .move { region.target = nil }
        }
    }

    func number(of id: UUID) -> Int {
        (regions.firstIndex { $0.id == id } ?? 0) + 1
    }

    /// Caja en píxeles de la versión actual.
    func pixelRect(_ r: CGRect) -> PixelRect {
        let size = current?.pixelSize ?? CGSize(width: 1000, height: 1000)
        return PixelRect(x: r.minX * size.width, y: r.minY * size.height, width: r.width * size.width, height: r.height * size.height)
    }

    func isTooSmall(_ region: RegionDraft) -> Bool {
        PreciseEdit.isTooSmall(pixelRect(region.rect)) || (region.target.map { PreciseEdit.isTooSmall(pixelRect($0)) } ?? false)
    }

    // MARK: - Referencias

    func setRegionReference(_ url: URL, for id: UUID) {
        let reference = EditReference(url: url)
        update(id) { $0.reference = reference }
        prepare(reference) { [weak self] ready in
            self?.update(id) { if $0.reference?.id == ready.id { $0.reference = ready } }
        }
    }

    func addExtraReferences(_ urls: [URL]) {
        for url in urls.filter(ReferenceImage.isSupported) where extraReferences.count + regionReferenceCount < 9 {
            let reference = EditReference(url: url)
            extraReferences.append(reference)
            prepare(reference) { [weak self] ready in
                guard let self, let i = self.extraReferences.firstIndex(where: { $0.id == ready.id }) else { return }
                self.extraReferences[i] = ready
            }
        }
    }

    private var regionReferenceCount: Int { regions.filter { $0.reference != nil }.count }

    private func prepare(_ reference: EditReference, completion: @escaping @MainActor (EditReference) -> Void) {
        let url = reference.url
        Task {
            var ready = reference
            ready.thumbnail = await ThumbnailLoader.load(url, maxPixelSize: 200)
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImageEncoder.Encoded, Error> in
                Result { try ImageEncoder.encode(fileURL: url) }
            }.value
            switch result {
            case .success(let encoded): ready.encoded = encoded
            case .failure(let error): ready.error = error.localizedDescription
            }
            completion(ready)
        }
    }

    // MARK: - Prompt

    /// Orden de `images`: [imagen actual, referencias de regiones…, referencias globales…].
    private var referenceLayout: (regionIndex: [UUID: Int], extra: [Int]) {
        var next = 1
        var map: [UUID: Int] = [:]
        for region in regions where region.reference != nil {
            map[region.id] = next
            next += 1
        }
        let extra = extraReferences.indices.map { next + $0 }
        return (map, extra)
    }

    var specs: [EditRegionSpec] {
        let layout = referenceLayout
        return regions.enumerated().map { index, region in
            let primary = pixelRect(region.rect)
            switch region.kind {
            case .new:
                return EditRegionSpec(number: index + 1, kind: .new, target: primary,
                                      instruction: region.instruction, referenceImageIndex: layout.regionIndex[region.id])
            case .move:
                return EditRegionSpec(number: index + 1, kind: .move, source: primary,
                                      target: region.target.map(pixelRect), instruction: region.instruction,
                                      referenceImageIndex: layout.regionIndex[region.id])
            case .edit, .anchor:
                return EditRegionSpec(number: index + 1, kind: region.kind, source: primary,
                                      instruction: region.instruction, referenceImageIndex: layout.regionIndex[region.id])
            }
        }
    }

    var automaticPrompt: String {
        let size = current?.pixelSize ?? CGSize(width: 1000, height: 1000)
        return PreciseEdit.buildPrompt(
            globalInstruction: globalInstruction, regions: specs,
            imageWidth: size.width, imageHeight: size.height,
            extraReferenceIndices: referenceLayout.extra
        )
    }

    var effectivePrompt: String { manualPrompt ?? automaticPrompt }

    /// Texto legible para el Historial (búsqueda).
    var summary: String {
        var parts: [String] = []
        let global = globalInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !global.isEmpty { parts.append(global) }
        for (i, r) in regions.enumerated() {
            parts.append("\(i + 1) [\(r.kind.spanishName)]: \(r.displayText)")
        }
        return parts.joined(separator: " · ")
    }

    var hasSomethingToDo: Bool {
        manualPrompt != nil
            || !globalInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || specs.contains { $0.isUsable && $0.kind != .anchor }
    }

    var referencesBusy: Bool {
        regions.contains { $0.reference?.isProcessing ?? false } || extraReferences.contains(where: \.isProcessing)
    }

    // MARK: - Generar

    func generate(using state: AppState) {
        guard let version = current, !isGenerating else { return }
        guard hasSomethingToDo else {
            state.alert = AppAlert(title: "Nada que editar", message: "Escribe qué debe cambiar en alguna región o un cambio para toda la imagen.")
            return
        }
        if let failed = (regions.compactMap(\.reference) + extraReferences).first(where: { $0.error != nil }) {
            state.alert = AppAlert(title: "Referencia no válida", message: "«\(failed.url.lastPathComponent)»: \(failed.error ?? "")")
            return
        }
        guard !referencesBusy else { return }
        let client: BFLClient
        do {
            client = try state.settings.makeClient()
        } catch {
            state.alert = AppAlert(title: "Falta la API key", message: error.localizedDescription, opensSettings: true)
            return
        }

        let prompt = effectivePrompt
        let summaryText = summary.isEmpty ? "Edición con precisión" : summary
        let regionRefs = regions.compactMap { $0.reference?.encoded?.base64 }
        let extraRefs = extraReferences.compactMap { $0.encoded?.base64 }
        let n = max(1, min(4, count))
        let parentIndex = currentIndex
        let sourceURL = version.fileURL
        let res = resolution, st = safety, gr = grounding

        isGenerating = true
        statusText = "Preparando imagen"
        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let base = try await Task.detached(priority: .userInitiated) {
                    try ImageEncoder.encode(fileURL: sourceURL)
                }.value
                let body = Flux3ImageRequest(
                    prompt: prompt, images: [base.base64] + regionRefs + extraRefs,
                    aspectRatio: "auto", resolution: res, safetyTolerance: st, grounding: gr
                )
                let parameters = (try? JSONValue(encoding: body))?.strippingLargeStrings() ?? .null
                statusText = "Enviando"

                var failures: [String] = []
                await withTaskGroup(of: Result<AppState.JobOutput, Error>.self) { group in
                    for index in 0..<n {
                        group.addTask { @MainActor in
                            do {
                                return .success(try await state.runJob(
                                    client: client, endpoint: .flux3Image, body: body,
                                    modelName: "Editar con precisión", prefix: "precise-edit", index: index,
                                    prompt: summaryText, sentPrompt: prompt, parameters: parameters,
                                    referenceCount: regionRefs.count + extraRefs.count
                                ) { [weak self] phase, _, _ in
                                    self?.statusText = Self.describe(phase)
                                })
                            } catch {
                                return .failure(error)
                            }
                        }
                    }
                    for await result in group {
                        switch result {
                        case .success(let output):
                            self.appendVersion(from: output, parent: parentIndex)
                        case .failure(let error):
                            if !(error is CancellationError) { failures.append(error.localizedDescription) }
                        }
                    }
                }
                if !failures.isEmpty {
                    state.alert = AppAlert(title: "No se ha podido editar", message: failures.first ?? "")
                }
            } catch is CancellationError {
            } catch {
                state.alert = AppAlert(title: "No se ha podido editar", message: error.localizedDescription)
            }
            self.isGenerating = false
            self.statusText = ""
            self.generationTask = nil
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
    }

    private func appendVersion(from output: AppState.JobOutput, parent: Int) {
        guard let image = NSImage(data: output.data) else { return }
        let size = ImageEncoder.pixelSize(fileURL: output.stored.fileURL).map { CGSize(width: $0.width, height: $0.height) } ?? image.size
        versions.append(EditVersion(fileURL: output.stored.fileURL, image: image, pixelSize: size, parentIndex: parent))
        currentIndex = versions.count - 1
    }

    static func describe(_ phase: ResultSlot.Phase) -> String {
        switch phase {
        case .submitting: return "Enviando"
        case .running(let s): return s.spanishLabel
        case .downloading: return "Descargando"
        default: return ""
        }
    }
}

extension CGRect {
    /// Recorta un rectángulo normalizado al cuadrado 0–1.
    var clampedToUnit: CGRect {
        var r = standardized
        r.size.width = min(max(r.width, 0.005), 1)
        r.size.height = min(max(r.height, 0.005), 1)
        r.origin.x = min(max(r.minX, 0), 1 - r.width)
        r.origin.y = min(max(r.minY, 0), 1 - r.height)
        return r
    }
}
