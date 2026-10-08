import Foundation

/// Metadatos que se guardan junto a cada resultado (.json).
public struct GenerationRecord: Codable, Sendable, Equatable {
    public var taskID: String
    public var endpoint: String
    public var model: String
    public var createdAt: Date
    public var prompt: String
    public var sentPrompt: String
    public var expandedPrompt: String?
    public var parameters: JSONValue
    public var cost: Double?
    public var inputMP: Double?
    public var outputMP: Double?
    public var region: String
    public var file: String
    public var referenceCount: Int?

    public init(
        taskID: String, endpoint: String, model: String, createdAt: Date = Date(),
        prompt: String, sentPrompt: String, expandedPrompt: String? = nil,
        parameters: JSONValue, cost: Double? = nil, inputMP: Double? = nil, outputMP: Double? = nil,
        region: String, file: String = "", referenceCount: Int? = nil
    ) {
        self.taskID = taskID
        self.endpoint = endpoint
        self.model = model
        self.createdAt = createdAt
        self.prompt = prompt
        self.sentPrompt = sentPrompt
        self.expandedPrompt = expandedPrompt
        self.parameters = parameters
        self.cost = cost
        self.inputMP = inputMP
        self.outputMP = outputMP
        self.region = region
        self.file = file
        self.referenceCount = referenceCount
    }
}

/// Un resultado guardado en disco (archivo + su .json).
public struct StoredResult: Identifiable, Sendable, Equatable {
    public let record: GenerationRecord
    public let fileURL: URL
    public let metadataURL: URL
    public var id: String { metadataURL.path }

    public init(record: GenerationRecord, fileURL: URL, metadataURL: URL) {
        self.record = record
        self.fileURL = fileURL
        self.metadataURL = metadataURL
    }

    public var isVideo: Bool {
        ["mp4", "mov"].contains(fileURL.pathExtension.lowercased())
    }
}

/// Guarda resultados en `<carpeta>/AAAA-MM-DD/` y los vuelve a leer para el Historial.
public enum ResultStore {
    public static func dayFolder(base: URL, date: Date = Date()) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return base.appendingPathComponent(f.string(from: date), isDirectory: true)
    }

    /// Escribe el archivo y su .json.
    public static func save(
        data: Data,
        mimeType: String?,
        sourceURL: URL?,
        base: URL,
        prefix: String,
        index: Int,
        record: GenerationRecord
    ) throws -> StoredResult {
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
        let metaURL = folder.appendingPathComponent(name).appendingPathExtension("json")
        try encoder.encode(meta).write(to: metaURL, options: .atomic)
        return StoredResult(record: meta, fileURL: fileURL, metadataURL: metaURL)
    }

    /// Lee todos los resultados guardados (más recientes primero).
    /// Ignora los .json que no son de la app y los que han perdido su archivo.
    public static func loadAll(base: URL) -> [StoredResult] {
        guard let enumerator = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [StoredResult] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(GenerationRecord.self, from: data),
                  !record.file.isEmpty else { continue }
            let file = url.deletingLastPathComponent().appendingPathComponent(record.file)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            results.append(StoredResult(record: record, fileURL: file, metadataURL: url))
        }
        return results.sorted { $0.record.createdAt > $1.record.createdAt }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
