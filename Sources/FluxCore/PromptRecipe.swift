import Foundation

/// Un prompt con sus parámetros: lo que se copia entre fotos («Copiar prompt y parámetros»)
/// y lo que se guarda en la biblioteca de «Prompts guardados», con título y explicación.
public struct PromptRecipe: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Explicación libre: para qué sirve, qué tener en cuenta…
    public var notes: String
    public var prompt: String
    /// Herramienta con la que se hizo (como en la barra lateral: «Generar», «Editar», «Collage»…).
    public var tool: String
    /// Ruta del endpoint de BFL (p. ej. `/v1/flux-3-image`), si se conoce.
    public var endpoint: String?
    /// Parámetros de la petición, sin imágenes (resolución, proporción, tolerancia…).
    public var parameters: JSONValue
    public var created: Date
    public var updated: Date
    /// Miniatura guardada junto a la biblioteca (nombre de archivo), si la hay.
    public var thumbnailFile: String?

    public init(id: UUID = UUID(), title: String, notes: String = "", prompt: String, tool: String,
                endpoint: String? = nil, parameters: JSONValue = .null, created: Date = Date(),
                updated: Date = Date(), thumbnailFile: String? = nil) {
        self.id = id
        self.title = title
        self.notes = notes
        self.prompt = prompt
        self.tool = tool
        self.endpoint = endpoint
        self.parameters = parameters
        self.created = created
        self.updated = updated
        self.thumbnailFile = thumbnailFile
    }

    /// Título por defecto: las primeras palabras del prompt.
    public static func defaultTitle(for prompt: String, words: Int = 6) -> String {
        let parts = prompt.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).prefix(words)
        let title = parts.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        guard !title.isEmpty else { return "Prompt sin título" }
        return parts.count < prompt.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count ? title + "…" : title
    }

    /// Ajustes de FLUX 3 Image que trae, si los trae.
    public var imageSettings: Flux3ImageSettings? {
        guard case .object(let o) = parameters, o["resolution"] != nil || o["aspect_ratio"] != nil else { return nil }
        return Flux3ImageSettings(parameters: parameters)
    }

    /// Resumen corto de los parámetros para mostrar («2K · 3:2 · tolerancia 2»).
    public var parameterSummary: String {
        var parts: [String] = []
        if let resolution = parameters["resolution"]?.stringValue {
            parts.append(Flux3Image.resolutionLabel(resolution).components(separatedBy: " · ").first ?? resolution)
        }
        if let ratio = parameters["aspect_ratio"]?.stringValue, ratio != "auto" { parts.append(ratio) }
        if let tolerance = parameters["safety_tolerance"]?.numberValue { parts.append("tolerancia \(Int(tolerance))") }
        return parts.joined(separator: " · ")
    }
}

/// Lectura y escritura de la biblioteca (`biblioteca.json`).
public enum PromptLibraryFile {
    public static let fileName = "biblioteca.json"

    public static func load(from url: URL) -> [PromptRecipe] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PromptRecipe].self, from: data)) ?? []
    }

    public static func save(_ recipes: [PromptRecipe], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(recipes).write(to: url, options: .atomic)
    }
}
