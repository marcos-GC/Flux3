import AppKit
import FluxCore
import SwiftUI

/// Asistente de prompts: chat con Claude (Sonnet u Opus) en un panel lateral. Analiza imágenes,
/// escribe prompts de FLUX 3 Image y los manda a Editar o a Generar con sus imágenes.
/// Las conversaciones se guardan en «<carpeta de salida>/Asistente».
@MainActor
final class AssistantStore: ObservableObject {
    @Published var isOpen = false
    @Published private(set) var conversation = PromptAssistant.Conversation()
    @Published var draft = ""
    /// Imágenes añadidas al mensaje que se está escribiendo.
    @Published var pending: [PromptAssistant.Attachment] = []
    @Published private(set) var isSending = false
    @Published var error: String?
    @Published private(set) var recent: [ConversationSummary] = []
    @Published var model: PromptAssistant.Model {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Self.modelKey) }
    }

    struct ConversationSummary: Identifiable, Equatable {
        let id: UUID
        let title: String
        let updatedAt: Date
        let url: URL
    }

    private let settings: SettingsStore
    private var sendTask: Task<Void, Never>?
    private static let modelKey = "assistantModel"

    init(settings: SettingsStore) {
        self.settings = settings
        model = UserDefaults.standard.string(forKey: Self.modelKey).flatMap(PromptAssistant.Model.init(rawValue:)) ?? .sonnet
    }

    var folder: URL { settings.outputFolder.appendingPathComponent("Asistente", isDirectory: true) }
    var extraGuideURL: URL { folder.appendingPathComponent("guia-flux-extra.md") }

    var canSend: Bool {
        !isSending && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pending.isEmpty)
    }

    /// Número que tendrá la próxima imagen (#N).
    private var nextNumber: Int {
        max(conversation.nextImageNumber, (pending.map(\.number).max() ?? 0) + 1)
    }

    // MARK: Imágenes

    func attach(_ urls: [URL], role: PromptAssistant.ImageRole? = nil) {
        for url in urls.filter(ReferenceImage.isSupported) {
            if pending.contains(where: { $0.path == url.path }) { continue }
            let size = ImageEncoder.pixelSize(fileURL: url)
            let chosenRole = role ?? defaultRole()
            pending.append(PromptAssistant.Attachment(
                number: nextNumber, fileURL: url, role: chosenRole,
                pixelWidth: size?.width, pixelHeight: size?.height
            ))
        }
        isOpen = true
    }

    /// La primera imagen es la que se transforma; las demás, referencias de estilo; tras una respuesta, resultados.
    private func defaultRole() -> PromptAssistant.ImageRole {
        if conversation.turns.contains(where: { $0.role == .assistant }) { return .result }
        let used = conversation.attachments + pending
        return used.contains { $0.role == .target } ? .style : .target
    }

    func setRole(_ role: PromptAssistant.ImageRole, for id: UUID) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].role = role
    }

    func removePending(_ id: UUID) {
        pending.removeAll { $0.id == id }
        // Renumera para que no queden huecos.
        let base = conversation.nextImageNumber
        for i in pending.indices { pending[i].number = base + i }
    }

    // MARK: Atajos

    enum QuickAction: CaseIterable, Identifiable {
        case deAI, styleMatch, improve

        var id: Self { self }

        var title: String {
            switch self {
            case .deAI: return "Quitar aspecto de IA"
            case .styleMatch: return "Llevar al estilo de una referencia"
            case .improve: return "Mejorar mi prompt"
            }
        }

        var icon: String {
            switch self {
            case .deAI: return "camera.aperture"
            case .styleMatch: return "paintpalette"
            case .improve: return "wand.and.stars"
            }
        }

        var text: String {
            switch self {
            case .deAI:
                return "Esta imagen se nota hecha con IA. Analiza qué la delata y escríbeme una edición sutil para que parezca una fotografía real y auténtica, sin cambiar la composición ni los objetos."
            case .styleMatch:
                return "Quiero que la imagen a transformar tenga el look de la referencia de estilo (color, luz, contraste, textura y mood), de forma sutil y sin cambiar su contenido ni su composición."
            case .improve:
                return "Mejora este prompt para FLUX 3 Image: "
            }
        }
    }

    func apply(_ action: QuickAction) {
        draft = action.text
        isOpen = true
    }

    // MARK: Enviar

    func send(focusedURL: URL?) {
        guard canSend else { return }
        var attachments = pending
        // Sin imágenes en toda la conversación, se usa la que está en grande.
        if attachments.isEmpty, conversation.attachments.isEmpty, let url = focusedURL, ReferenceImage.isSupported(url) {
            let size = ImageEncoder.pixelSize(fileURL: url)
            attachments = [PromptAssistant.Attachment(number: nextNumber, fileURL: url, role: .target,
                                                       pixelWidth: size?.width, pixelHeight: size?.height)]
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let turn = PromptAssistant.Turn(role: .user, text: text, attachments: attachments)
        conversation.turns.append(turn)
        if conversation.title.isEmpty { conversation.title = Self.title(from: text) }
        draft = ""
        pending = []
        error = nil
        save()
        request()
    }

    /// Vuelve a pedir la última respuesta (tras un error).
    func retry() {
        guard !isSending, conversation.turns.last?.role == .user else { return }
        error = nil
        request()
    }

    func cancel() {
        sendTask?.cancel()
    }

    private func request() {
        let turns = conversation.turns
        let model = self.model
        let system = guideText()
        let conversationID = conversation.id
        let key: String
        do {
            key = try settings.anthropicKey()
        } catch {
            self.error = "Falta la API key de Anthropic. Pégala en Ajustes → «Mejorar prompts con Claude»."
            return
        }
        isSending = true
        sendTask = Task { [weak self] in
            do {
                let reply = try await PromptAssistant.send(
                    turns: turns, model: model, system: system, apiKey: key,
                    image: { Self.encode($0) }
                )
                guard let self, self.conversation.id == conversationID else { return }
                var text = reply.text
                if reply.truncated { text += "\n\n(La respuesta se ha cortado por larga. Pídele que siga.)" }
                self.conversation.turns.append(PromptAssistant.Turn(
                    role: .assistant, text: text, rawContent: reply.rawContent, model: reply.model ?? model.rawValue
                ))
                self.save()
            } catch is CancellationError {
                self?.error = "Cancelado."
            } catch {
                self?.error = error.localizedDescription
            }
            self?.isSending = false
        }
    }

    nonisolated private static func encode(_ attachment: PromptAssistant.Attachment) -> PromptAssistant.EncodedImage? {
        guard let encoded = try? ImageEncoder.encode(fileURL: attachment.fileURL,
                                                     maxDimension: PromptAssistant.imageMaxDimension) else { return nil }
        return PromptAssistant.EncodedImage(mediaType: encoded.isPNG ? "image/png" : "image/jpeg", base64: encoded.base64)
    }

    /// Guía de FLUX + lo que el estudio añada en «Asistente/guia-flux-extra.md».
    private func guideText() -> String {
        guard let extra = try? String(contentsOf: extraGuideURL, encoding: .utf8),
              !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return FluxGuide.text }
        return FluxGuide.text + "\n\n# Notas propias del estudio (tienen prioridad)\n\n" + extra
    }

    private static func title(from text: String) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        guard !clean.isEmpty else { return "Conversación con imágenes" }
        return clean.count > 60 ? String(clean.prefix(57)) + "…" : clean
    }

    // MARK: Conversaciones

    func newConversation() {
        sendTask?.cancel()
        isSending = false
        conversation = PromptAssistant.Conversation()
        pending = []
        draft = ""
        error = nil
    }

    private var conversationURL: URL {
        folder.appendingPathComponent("conversacion_\(conversation.id.uuidString.prefix(8).lowercased()).json")
    }

    private func save() {
        guard !conversation.turns.isEmpty else { return }
        conversation.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(conversation).write(to: conversationURL, options: .atomic)
        } catch {
            self.error = "No se ha podido guardar la conversación: \(error.localizedDescription)"
        }
        loadRecent()
    }

    func loadRecent() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        recent = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("conversacion_") }
            .compactMap { url -> ConversationSummary? in
                guard let data = try? Data(contentsOf: url),
                      let c = try? decoder.decode(PromptAssistant.Conversation.self, from: data) else { return nil }
                return ConversationSummary(id: c.id, title: c.title.isEmpty ? "Sin título" : c.title,
                                           updatedAt: c.updatedAt, url: url)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map { $0 }
    }

    func open(_ summary: ConversationSummary) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: summary.url),
              let c = try? decoder.decode(PromptAssistant.Conversation.self, from: data) else {
            error = "No se ha podido abrir la conversación."
            return
        }
        newConversation()
        conversation = c
    }

    func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: extraGuideURL.path) {
            let template = """
            <!-- Notas propias para el Asistente de prompts. Lo que escribas aquí se añade a la guía de FLUX 3
                 en cada conversación y tiene prioridad. Por ejemplo: estilo de la casa, cámaras y ópticas que
                 usáis, materiales habituales, cosas que FLUX os hace mal y cómo lo corregís. -->

            """
            try? template.write(to: extraGuideURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([extraGuideURL])
    }

    // MARK: Usar un prompt

    /// Archivos de la sugerencia, en el orden de FLUX (image 1, image 2…). Los que ya no existen se omiten.
    func files(for suggestion: PromptAssistant.Suggestion) -> [URL] {
        suggestion.images.compactMap { conversation.attachment(number: $0)?.fileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func use(_ suggestion: PromptAssistant.Suggestion, as target: PromptAssistant.Target, state: AppState) {
        let urls = files(for: suggestion)
        if urls.count < suggestion.images.count {
            state.alert = AppAlert(title: "Falta alguna imagen",
                                   message: "Alguna de las imágenes que cita el prompt ya no está en el disco. Revisa las referencias antes de generar.")
        }
        switch target {
        case .edit:
            guard let base = urls.first else {
                state.alert = AppAlert(title: "No hay imagen que editar",
                                       message: "Este prompt no cita ninguna imagen. Úsalo en Generar o pídele al asistente que lo prepare como edición.")
                return
            }
            state.focus(base, tool: .edit)
            let edit = state.preciseEdit
            // Se carga ya (sin esperar a la vista) para poder poner el prompt encima.
            edit.sync(with: base, parent: state.parent(of: base))
            edit.clearRegions()
            edit.extraReferences = []
            edit.addExtraReferences(Array(urls.dropFirst()))
            edit.manualPrompt = suggestion.prompt
            if let r = suggestion.resolution, Flux3Image.editResolutions.contains(r) { edit.resolution = r }
            state.notice = "Prompt del asistente en Editar · «Ver prompt» para revisarlo"
        case .generate:
            state.selectTool(.generate)
            state.focusedURL = nil
            state.prompt = suggestion.prompt
            state.references.removeAll()
            if !urls.isEmpty { state.addReferences(urls) }
            if let ar = suggestion.aspectRatio, Flux3Image.aspectRatios.contains(ar) { state.imageParams.aspectRatio = ar }
            if let r = suggestion.resolution, Flux3Image.resolutions.contains(r) { state.imageParams.resolution = r }
            state.notice = "Prompt del asistente en Generar"
        }
    }

    func copy(_ suggestion: PromptAssistant.Suggestion) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(suggestion.prompt, forType: .string)
    }
}
