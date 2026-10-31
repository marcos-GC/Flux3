import AppKit
import FluxCore
import ImageIO
import UniformTypeIdentifiers

/// «Prompts guardados»: biblioteca de prompts con sus parámetros, título y explicación.
/// Se guarda en «<carpeta de salida>/Prompts guardados/biblioteca.json» (más miniaturas).
@MainActor
final class PromptLibrary: ObservableObject {
    @Published private(set) var recipes: [PromptRecipe] = []
    private let settings: SettingsStore
    private var loadedFolder: URL?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var folder: URL {
        settings.outputFolder.appendingPathComponent("Prompts guardados", isDirectory: true)
    }

    private var fileURL: URL { folder.appendingPathComponent(PromptLibraryFile.fileName) }

    /// Lee la biblioteca (si ha cambiado la carpeta de salida o no se ha leído aún).
    func reloadIfNeeded() {
        guard loadedFolder != folder else { return }
        recipes = PromptLibraryFile.load(from: fileURL).sorted { $0.updated > $1.updated }
        loadedFolder = folder
    }

    func thumbnailURL(_ recipe: PromptRecipe) -> URL? {
        recipe.thumbnailFile.map { folder.appendingPathComponent("miniaturas").appendingPathComponent($0) }
    }

    /// Guarda (nueva o editada). Con `image`, guarda también una miniatura.
    func save(_ recipe: PromptRecipe, image: URL? = nil) {
        reloadIfNeeded()
        var r = recipe
        r.updated = Date()
        if let image, r.thumbnailFile == nil, let name = writeThumbnail(from: image, id: r.id) {
            r.thumbnailFile = name
        }
        if let i = recipes.firstIndex(where: { $0.id == r.id }) {
            recipes[i] = r
        } else {
            recipes.insert(r, at: 0)
        }
        recipes.sort { $0.updated > $1.updated }
        persist()
    }

    func delete(_ recipe: PromptRecipe) {
        reloadIfNeeded()
        recipes.removeAll { $0.id == recipe.id }
        if let url = thumbnailURL(recipe) { try? FileManager.default.removeItem(at: url) }
        persist()
    }

    private func persist() {
        do {
            try PromptLibraryFile.save(recipes, to: fileURL)
        } catch {
            NSSound.beep()
        }
    }

    private func writeThumbnail(from url: URL, id: UUID) -> String? {
        guard let image = ImageEncoder.thumbnail(fileURL: url, maxPixelSize: 480) else { return nil }
        let dir = folder.appendingPathComponent("miniaturas", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(id.uuidString).jpg"
        guard let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent(name) as CFURL,
                                                         UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? name : nil
    }
}

/// Borrador abierto en la hoja de «Guardar en Prompts guardados».
struct RecipeDraft: Identifiable {
    var recipe: PromptRecipe
    /// Imagen de la que sacar la miniatura (si se guarda desde una foto).
    var image: URL?
    var isNew: Bool
    var id: UUID { recipe.id }
}

// MARK: - Copiar, pegar y aplicar

extension AppState {
    /// Prompt y parámetros de un resultado guardado.
    func recipe(for url: URL) -> PromptRecipe? {
        guard let record = history.items.first(where: { $0.fileURL == url })?.record else { return nil }
        let text = record.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return PromptRecipe(title: PromptRecipe.defaultTitle(for: text), prompt: text,
                            tool: ToolNames.display(record.model), endpoint: record.endpoint,
                            parameters: record.parameters)
    }

    /// Lo que hay escrito ahora en la herramienta abierta, con sus parámetros.
    func currentRecipe() -> PromptRecipe? {
        let text: String
        var parameters: [String: JSONValue] = [:]
        switch tool {
        case .edit:
            text = preciseEdit.globalInstruction
            parameters = ["resolution": .string(preciseEdit.resolution), "safety_tolerance": .number(Double(preciseEdit.safety)),
                          "grounding": .bool(preciseEdit.grounding)]
        case .collage:
            text = collage.extraPrompt
            parameters = ["resolution": .string(collage.resolution), "safety_tolerance": .number(Double(collage.safety))]
        case .video:
            text = video.prompt
        case .outpaint:
            text = outpaint.prompt
        case .fill:
            text = fill.prompt
            parameters = ["resolution": .string(fill.resolution), "safety_tolerance": .number(Double(fill.safety))]
        default:
            text = prompt
            parameters = ["aspect_ratio": .string(imageParams.aspectRatio), "resolution": .string(imageParams.resolution),
                          "safety_tolerance": .number(Double(imageParams.safety)), "grounding": .bool(imageParams.grounding)]
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        return PromptRecipe(title: PromptRecipe.defaultTitle(for: clean), prompt: clean,
                            tool: tool == .generate || !tool.hasPromptField ? WorkspaceTool.generate.title : tool.title,
                            endpoint: BFLEndpoint.flux3Image.path, parameters: .object(parameters))
    }

    /// «Copiar prompt y parámetros» de una foto (también deja el texto en el portapapeles).
    func copyRecipe(from url: URL) {
        guard let recipe = recipe(for: url) else {
            alert = AppAlert(title: "Sin prompt", message: "Esta imagen no tiene prompt guardado (por ejemplo, si se abrió desde el Mac).")
            return
        }
        copiedRecipe = recipe
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(recipe.prompt, forType: .string)
        notice = "Prompt y parámetros copiados. Pégalos con ⌥⌘V en la herramienta que quieras."
    }

    /// «Pegar prompt y parámetros» en la herramienta abierta.
    func pasteRecipe() {
        guard let copiedRecipe else { return }
        apply(copiedRecipe)
    }

    /// Pone el prompt y los parámetros en la herramienta abierta. Si la herramienta no tiene
    /// caja de texto (Borrar, Deblur, Probador), se va a Generar.
    func apply(_ recipe: PromptRecipe) {
        if mode != .generate { mode = .generate }
        if !tool.hasPromptField { selectTool(.generate) }
        let settings = recipe.imageSettings
        switch tool {
        case .edit:
            preciseEdit.globalInstruction = recipe.prompt
            if let s = settings {
                preciseEdit.resolution = s.resolution
                preciseEdit.safety = s.safetyTolerance
                preciseEdit.grounding = s.grounding
            }
        case .collage:
            collage.extraPrompt = recipe.prompt
            if let s = settings {
                collage.resolution = s.resolution
                collage.safety = s.safetyTolerance
            }
        case .video:
            video.prompt = recipe.prompt
        case .outpaint:
            outpaint.prompt = recipe.prompt
        case .fill:
            fill.prompt = recipe.prompt
            if let s = settings {
                fill.resolution = s.resolution
                fill.safety = s.safetyTolerance
            }
        default:
            prompt = recipe.prompt
            if let s = settings {
                imageParams.aspectRatio = s.aspectRatio
                imageParams.resolution = s.resolution
                imageParams.safety = s.safetyTolerance
                imageParams.grounding = s.grounding
            }
        }
        notice = "«\(recipe.title)» puesto en \(tool.title)."
    }

    /// Abre la hoja para guardar en «Prompts guardados».
    func saveRecipe(from url: URL) {
        guard let recipe = recipe(for: url) else {
            alert = AppAlert(title: "Sin prompt", message: "Esta imagen no tiene prompt guardado.")
            return
        }
        recipeDraft = RecipeDraft(recipe: recipe, image: url, isNew: true)
    }

    func saveCurrentRecipe() {
        guard let recipe = currentRecipe() else {
            alert = AppAlert(title: "No hay nada escrito", message: "Escribe primero el prompt que quieres guardar.")
            return
        }
        recipeDraft = RecipeDraft(recipe: recipe, image: focusedURL.flatMap { VideoModel.isVideo($0) ? nil : $0 }, isNew: true)
    }
}

extension WorkspaceTool {
    /// Herramientas con caja de texto donde pegar un prompt.
    var hasPromptField: Bool {
        switch self {
        case .generate, .edit, .fill, .collage, .video, .outpaint: return true
        case .erase, .deblur, .tryOn: return false
        }
    }
}
