import Foundation

/// Asistente de prompts: conversación con Claude (Sonnet u Opus) con imágenes, que escribe
/// prompts de FLUX 3 Image siguiendo `FluxGuide`. Messages API por HTTPS.
public enum PromptAssistant {
    public static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2023-06-01"
    /// Si un filtro de seguridad rechaza la petición, la API la repite con otro modelo adecuado.
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Lado largo de las imágenes que se envían a Claude (más grande no le aporta y encarece).
    public static let imageMaxDimension = 1568
    /// Máximo de imágenes que se envían en una petición (las más recientes).
    public static let maxImagesPerRequest = 20

    public enum Model: String, Codable, CaseIterable, Sendable, Identifiable {
        case sonnet = "claude-sonnet-5-5"
        case opus = "claude-opus-5-5"

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .sonnet: return "Sonnet"
            case .opus: return "Opus"
            }
        }

        public var detail: String {
            switch self {
            case .sonnet: return "Rápido y suficiente para casi todo"
            case .opus: return "Más fino en casos difíciles; más lento y caro"
            }
        }
    }

    /// Papel de cada imagen en la conversación.
    public enum ImageRole: String, Codable, CaseIterable, Sendable, Identifiable {
        case target, style, reference, result

        public var id: String { rawValue }

        public var spanishName: String {
            switch self {
            case .target: return "Imagen a transformar"
            case .style: return "Referencia de estilo"
            case .reference: return "Referencia"
            case .result: return "Resultado"
            }
        }

        public var icon: String {
            switch self {
            case .target: return "photo"
            case .style: return "paintpalette"
            case .reference: return "square.on.square"
            case .result: return "checkmark.seal"
            }
        }
    }

    public struct Attachment: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        /// Número de la imagen en la conversación (#1, #2…).
        public var number: Int
        public var path: String
        public var role: ImageRole
        public var pixelWidth: Int?
        public var pixelHeight: Int?

        public init(id: UUID = UUID(), number: Int, fileURL: URL, role: ImageRole,
                    pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
            self.id = id
            self.number = number
            self.path = fileURL.path
            self.role = role
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
        }

        public var fileURL: URL { URL(fileURLWithPath: path) }

        /// Línea que acompaña a la imagen en el mensaje.
        public var label: String {
            var text = "Imagen #\(number) · \(role.spanishName.lowercased()) · archivo «\(fileURL.lastPathComponent)»"
            if let w = pixelWidth, let h = pixelHeight { text += " · \(w)×\(h) px" }
            return text
        }
    }

    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public struct Turn: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var role: Role
        /// Lo que escribió el usuario, o el texto visible de la respuesta.
        public var text: String
        public var attachments: [Attachment]
        /// Respuesta completa de Claude (bloques de contenido), que se reenvía tal cual en los turnos siguientes.
        public var rawContent: JSONValue?
        /// Modelo que respondió.
        public var model: String?
        public var createdAt: Date

        public init(id: UUID = UUID(), role: Role, text: String, attachments: [Attachment] = [],
                    rawContent: JSONValue? = nil, model: String? = nil, createdAt: Date = Date()) {
            self.id = id
            self.role = role
            self.text = text
            self.attachments = attachments
            self.rawContent = rawContent
            self.model = model
            self.createdAt = createdAt
        }
    }

    public struct Conversation: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var createdAt: Date
        public var updatedAt: Date
        public var turns: [Turn]
        public var guideVersion: String?

        public init(id: UUID = UUID(), title: String = "", createdAt: Date = Date(), turns: [Turn] = []) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
            self.updatedAt = createdAt
            self.turns = turns
            self.guideVersion = FluxGuide.version
        }

        public var attachments: [Attachment] { turns.flatMap(\.attachments) }
        public var nextImageNumber: Int { (attachments.map(\.number).max() ?? 0) + 1 }

        public func attachment(number: Int) -> Attachment? {
            attachments.last { $0.number == number }
        }
    }

    // MARK: - Prompts propuestos

    public enum Target: String, Sendable, Equatable {
        case edit, generate
    }

    public struct Suggestion: Sendable, Equatable {
        public var target: Target
        /// Números #N de las imágenes, en el orden en que FLUX las recibe (image 1, image 2…).
        public var images: [Int]
        public var aspectRatio: String?
        public var resolution: String?
        public var prompt: String
    }

    public enum Segment: Sendable, Equatable {
        case text(String)
        case prompt(Suggestion)
    }

    /// Divide la respuesta en texto y bloques `<prompt …>…</prompt>`.
    public static func segments(_ text: String) -> [Segment] {
        var result: [Segment] = []
        var rest = Substring(text)
        func appendText(_ s: Substring) {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty { result.append(.text(clean)) }
        }
        while let open = rest.range(of: "<prompt") {
            guard let tagEnd = rest[open.upperBound...].firstIndex(of: ">"),
                  let close = rest[tagEnd...].range(of: "</prompt>") else { break }
            appendText(rest[..<open.lowerBound])
            let attributes = parseAttributes(String(rest[open.upperBound..<tagEnd]))
            let body = rest[rest.index(after: tagEnd)..<close.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                let target = Target(rawValue: attributes["target"]?.lowercased() ?? "") ?? .generate
                let images = (attributes["images"] ?? "")
                    .split(whereSeparator: { $0 == "," || $0 == " " })
                    .compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "# "))) }
                result.append(.prompt(Suggestion(
                    target: target, images: images,
                    aspectRatio: attributes["aspect_ratio"].flatMap { $0.isEmpty ? nil : $0 },
                    resolution: attributes["resolution"].flatMap { $0.isEmpty ? nil : $0 },
                    prompt: body
                )))
            }
            rest = rest[close.upperBound...]
        }
        appendText(rest)
        return result
    }

    public static func suggestions(in text: String) -> [Suggestion] {
        segments(text).compactMap { if case .prompt(let s) = $0 { return s } else { return nil } }
    }

    /// `name="value"` (también con comillas simples o tipográficas).
    static func parseAttributes(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        let normalized = raw.replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "'", with: "\"")
        let pattern = #"([A-Za-z_]+)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = normalized as NSString
        for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
            result[ns.substring(with: match.range(at: 1)).lowercased()] = ns.substring(with: match.range(at: 2))
        }
        return result
    }

    // MARK: - Petición

    /// Imagen ya preparada para enviar (JPEG o PNG en base64).
    public struct EncodedImage: Sendable {
        public let mediaType: String
        public let base64: String

        public init(mediaType: String, base64: String) {
            self.mediaType = mediaType
            self.base64 = base64
        }
    }

    public static func requestBody(
        turns: [Turn], model: Model, system: String,
        image: (Attachment) -> EncodedImage?
    ) throws -> Data {
        // Solo se mandan las imágenes más recientes (las anteriores quedan citadas por su etiqueta).
        let allNumbers = turns.flatMap(\.attachments).map(\.id)
        let sentIDs = Set(allNumbers.suffix(maxImagesPerRequest))

        var messages: [JSONValue] = []
        for turn in turns {
            switch turn.role {
            case .assistant:
                if let raw = turn.rawContent, case .array(let blocks) = raw, !blocks.isEmpty {
                    messages.append(.object(["role": .string("assistant"), "content": raw]))
                } else {
                    messages.append(.object(["role": .string("assistant"), "content": .string(turn.text)]))
                }
            case .user:
                var content: [JSONValue] = []
                for attachment in turn.attachments {
                    if sentIDs.contains(attachment.id), let encoded = image(attachment) {
                        content.append(.object(["type": .string("text"), "text": .string(attachment.label)]))
                        content.append(.object([
                            "type": .string("image"),
                            "source": .object([
                                "type": .string("base64"),
                                "media_type": .string(encoded.mediaType),
                                "data": .string(encoded.base64),
                            ]),
                        ]))
                    } else {
                        content.append(.object(["type": .string("text"),
                                                "text": .string(attachment.label + " (no se adjunta de nuevo en este mensaje)")]))
                    }
                }
                let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
                content.append(.object(["type": .string("text"),
                                        "text": .string(text.isEmpty ? "(sin texto: mira las imágenes)" : text)]))
                messages.append(.object(["role": .string("user"), "content": .array(content)]))
            }
        }

        let body: JSONValue = .object([
            "model": .string(model.rawValue),
            "max_tokens": .number(16000),
            "thinking": .object(["type": .string("adaptive")]),
            "output_config": .object(["effort": .string("medium")]),
            // La guía es larga y fija: se cachea. El caché automático cubre además la conversación.
            "system": .array([.object([
                "type": .string("text"),
                "text": .string(system),
                "cache_control": .object(["type": .string("ephemeral")]),
            ])]),
            "cache_control": .object(["type": .string("ephemeral")]),
            "fallbacks": .string("default"),
            "messages": .array(messages),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(body)
    }

    // MARK: - Respuesta

    public struct Reply: Sendable, Equatable {
        public let text: String
        public let rawContent: JSONValue
        public let model: String?
        public let truncated: Bool
    }

    public enum AssistantError: LocalizedError, Equatable {
        case refused
        case noText
        case http(status: Int, message: String?)

        public var errorDescription: String? {
            switch self {
            case .refused: return "Claude ha preferido no responder a esta petición. Prueba a reformularla."
            case .noText: return "Claude no ha devuelto ninguna respuesta."
            case let .http(status, message):
                let extra = message.map { " Detalle: \($0)" } ?? ""
                switch status {
                case 401: return "La API key de Anthropic no es válida. Revísala en Ajustes."
                case 402: return "Problema de facturación en tu cuenta de Anthropic (¿sin saldo?)." + extra
                case 403, 404: return "Tu API key de Anthropic no puede usar este modelo de Claude." + extra
                case 413: return "Demasiadas imágenes o demasiado grandes en la conversación. Empieza una conversación nueva." + extra
                case 429: return "Demasiadas peticiones a Claude en poco tiempo. Espera unos segundos y vuelve a probar."
                case 529: return "Los servidores de Claude están saturados ahora mismo. Inténtalo en un momento."
                case 500...599: return "Error temporal de Anthropic (\(status)). Inténtalo de nuevo."
                default: return "Error \(status) de la API de Anthropic." + extra
                }
            }
        }
    }

    public static func parseReply(_ data: Data) throws -> Reply {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let stop = json["stop_reason"]?.stringValue
        if stop == "refusal" { throw AssistantError.refused }
        guard case .array(let blocks)? = json["content"] else { throw AssistantError.noText }
        let text = blocks
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AssistantError.noText }
        return Reply(text: text, rawContent: .array(blocks), model: json["model"]?.stringValue,
                     truncated: stop == "max_tokens")
    }

    // MARK: - Llamada

    public static func send(
        turns: [Turn], model: Model, system: String, apiKey: String,
        image: @escaping @Sendable (Attachment) -> EncodedImage?,
        session: URLSession = .shared
    ) async throws -> Reply {
        guard !apiKey.isEmpty else { throw PromptEnhancer.EnhanceError.missingKey }
        let body = try await Task.detached(priority: .userInitiated) {
            try requestBody(turns: turns, model: model, system: system, image: image)
        }.value
        var request = URLRequest(url: messagesURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Con imágenes y razonamiento, una respuesta de Opus puede tardar varios minutos.
        request.timeoutInterval = 600
        request.httpBody = body

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw PromptEnhancer.EnhanceError.network(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AssistantError.http(status: http.statusCode, message: PromptEnhancer.errorMessage(from: data))
        }
        return try parseReply(data)
    }
}
