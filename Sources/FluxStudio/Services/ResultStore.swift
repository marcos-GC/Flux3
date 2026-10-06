import FluxCore
import Foundation

/// Metadatos que se guardan junto a cada resultado (.json).
struct GenerationRecord: Codable {
    var taskID: String
    var endpoint: String
    var model: String
    var createdAt: Date
    var prompt: String
    var sentPrompt: String
    var expandedPrompt: String?
    var parameters: JSONValue
    var cost: Double?
    var inputMP: Double?
    var outputMP: Double?
    var region: String
    var file: String
}

/// Guarda resultados en `<carpeta>/AAAA-MM-DD/`.
enum ResultStore {
    static func dayFolder(base: URL, date: Date = Date()) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return base.appendingPathComponent(f.string(from: date), isDirectory: true)
    }

    /// Escribe el archivo y su .json. Devuelve la URL del archivo.
    static func save(
        data: Data,
        mimeType: String?,
        sourceURL: URL,
        base: URL,
        prefix: String,
        index: Int,
        record: GenerationRecord
    ) throws -> URL {
        let folder = dayFolder(base: base, date: record.createdAt)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HHmmss"
        let ext = MediaType.fileExtension(mimeType: mimeType, url: sourceURL)
        let name = "\(prefix)_\(time.string(from: record.createdAt))_\(record.taskID.prefix(8))_\(index + 1)"
        let fileURL = folder.appendingPathComponent(name).appendingPathExtension(ext)
        try data.write(to: fileURL, options: .atomic)

        var meta = record
        meta.file = fileURL.lastPathComponent
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(meta).write(to: folder.appendingPathComponent(name).appendingPathExtension("json"), options: .atomic)
        return fileURL
    }
}
