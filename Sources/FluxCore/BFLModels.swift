import Foundation

/// Respuesta del POST: `{ id, polling_url, cost, input_mp, output_mp }`.
public struct SubmitResponse: Decodable, Sendable, Equatable {
    public let id: String
    public let pollingURL: String
    public let cost: Double?
    public let inputMP: Double?
    public let outputMP: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case pollingURL = "polling_url"
        case cost
        case inputMP = "input_mp"
        case outputMP = "output_mp"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        pollingURL = try c.decode(String.self, forKey: .pollingURL)
        cost = Self.flexibleNumber(c, .cost)
        inputMP = Self.flexibleNumber(c, .inputMP)
        outputMP = Self.flexibleNumber(c, .outputMP)
    }

    /// Acepta número o texto numérico, y nunca falla si el campo cambia de tipo.
    private static func flexibleNumber(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }
}

/// Resultado de una tarea lista. Imagen: `sample` (+ `prompt` expandido).
/// Vídeo: `samples` y `draft_caches` son listas.
public struct PollResult: Decodable, Sendable, Equatable {
    public let sample: String?
    public let samples: [String]
    public let prompt: String?
    public let draftCaches: [String]
    public let seed: Double?
    public let raw: JSONValue?

    enum CodingKeys: String, CodingKey {
        case sample, samples, prompt, seed
        case draftCache = "draft_cache"
        case draftCaches = "draft_caches"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sample = try? c.decodeIfPresent(String.self, forKey: .sample)
        samples = (try? c.decodeIfPresent([String].self, forKey: .samples)) ?? []
        prompt = try? c.decodeIfPresent(String.self, forKey: .prompt)
        seed = try? c.decodeIfPresent(Double.self, forKey: .seed)
        var caches = (try? c.decodeIfPresent([String].self, forKey: .draftCaches)) ?? []
        if caches.isEmpty, let single = try? c.decodeIfPresent(String.self, forKey: .draftCache) {
            caches = [single]
        }
        draftCaches = caches
        raw = try? JSONValue(from: decoder)
    }

    /// Todas las URLs de resultado, sin duplicados y en orden.
    public var sampleURLs: [URL] {
        var seen = Set<String>()
        return ([sample].compactMap { $0 } + samples)
            .filter { seen.insert($0).inserted }
            .compactMap(URL.init(string:))
    }
}

/// Respuesta del GET a la `polling_url`.
public struct PollResponse: Decodable, Sendable, Equatable {
    public let id: String?
    public let status: BFLStatus
    public let result: PollResult?
    public let progress: Double?
    public let details: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, status, result, progress, details
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        status = try c.decode(BFLStatus.self, forKey: .status)
        result = try? c.decodeIfPresent(PollResult.self, forKey: .result)
        progress = try? c.decodeIfPresent(Double.self, forKey: .progress)
        details = try? c.decodeIfPresent(JSONValue.self, forKey: .details)
    }
}
