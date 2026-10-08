import Foundation

/// Mejora prompts con Claude Haiku (API de Anthropic, Messages API por HTTPS).
public enum PromptEnhancer {
    public static let model = "claude-haiku-5-5"
    public static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let modelInfoURL = URL(string: "https://api.anthropic.com/v1/models/claude-haiku-5-5")!
    public static let apiVersion = "2023-06-01"

    public enum Kind: String, Sendable {
        case image, video
    }

    /// Lo que la app sabe de la petición y ayuda a mejorar el prompt.
    public struct Context: Sendable, Equatable {
        public var kind: Kind
        public var referenceCount: Int
        public var aspectRatio: String?
        /// Para vídeo: «texto a vídeo», «imagen a vídeo»…
        public var videoMode: String?
        public var keyframeCount: Int

        public init(kind: Kind, referenceCount: Int = 0, aspectRatio: String? = nil,
                    videoMode: String? = nil, keyframeCount: Int = 0) {
            self.kind = kind
            self.referenceCount = referenceCount
            self.aspectRatio = aspectRatio
            self.videoMode = videoMode
            self.keyframeCount = keyframeCount
        }
    }

    public struct Result: Sendable, Equatable {
        public let prompt: String
        /// Qué se ha cambiado, en español.
        public let notes: String?
    }

    public enum EnhanceError: LocalizedError, Equatable {
        case missingKey
        case emptyPrompt
        case http(status: Int, message: String?)
        case refused
        case noText
        case network(String)

        public var errorDescription: String? {
            switch self {
            case .missingKey:
                return "Falta la API key de Anthropic. Pégala en Ajustes → «Mejorar prompts con Claude»."
            case .emptyPrompt:
                return "Escribe primero una idea para que Claude la mejore."
            case let .http(status, message):
                let extra = message.map { " Detalle: \($0)" } ?? ""
                switch status {
                case 401: return "La API key de Anthropic no es válida. Revísala en Ajustes."
                case 402: return "Problema de facturación en tu cuenta de Anthropic (¿sin saldo?)." + extra
                case 403: return "Esta API key de Anthropic no tiene permiso para usar Claude Haiku." + extra
                case 404: return "El modelo Claude Haiku no está disponible para tu cuenta de Anthropic." + extra
                case 429: return "Demasiadas peticiones a Claude en poco tiempo. Espera unos segundos y vuelve a probar."
                case 529: return "Los servidores de Claude están saturados ahora mismo. Inténtalo en un momento."
                case 500...599: return "Error temporal de Anthropic (\(status)). Inténtalo de nuevo."
                default: return "Error \(status) de la API de Anthropic." + extra
                }
            case .refused:
                return "Claude ha preferido no reescribir este prompt. Prueba a reformularlo."
            case .noText:
                return "Claude no ha devuelto ningún prompt."
            case .network(let what):
                return "Problema de conexión con Anthropic: \(what)"
            }
        }
    }

    // MARK: - Petición

    public static func requestBody(userPrompt: String, context: Context) throws -> Data {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8000,
            // Reescribir un prompt es una tarea sencilla: esfuerzo bajo = más rápido y barato.
            "output_config": ["effort": "low"],
            // El prompt de sistema es largo y fijo: se cachea para abaratar las siguientes peticiones.
            "system": [[
                "type": "text",
                "text": systemPrompt(for: context.kind),
                "cache_control": ["type": "ephemeral"],
            ]],
            "messages": [[
                "role": "user",
                "content": userMessage(userPrompt: userPrompt, context: context),
            ]],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func userMessage(userPrompt: String, context: Context) -> String {
        var lines: [String] = []
        switch context.kind {
        case .image:
            lines.append("<tipo>FLUX 3 Image</tipo>")
            if context.referenceCount > 0 {
                let list = (1...context.referenceCount).map { "image \($0)" }.joined(separator: ", ")
                lines.append("<referencias>Hay \(context.referenceCount) imagen(es) de referencia adjunta(s), en este orden: \(list).</referencias>")
            } else {
                lines.append("<referencias>Ninguna: es texto a imagen.</referencias>")
            }
            if let ar = context.aspectRatio, ar != "auto" {
                lines.append("<proporcion>\(ar)</proporcion>")
            }
        case .video:
            lines.append("<tipo>FLUX 3 Video</tipo>")
            if let mode = context.videoMode { lines.append("<modo>\(mode)</modo>") }
            if context.keyframeCount > 0 {
                lines.append("<fotogramas_clave>\(context.keyframeCount) imagen(es) fijadas en pantalla, en orden.</fotogramas_clave>")
            }
            if let ar = context.aspectRatio, ar != "auto" {
                lines.append("<proporcion>\(ar)</proporcion>")
            }
        }
        lines.append("<prompt_usuario>\n\(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines))\n</prompt_usuario>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Respuesta

    /// Extrae `<prompt>` y `<notas>` del texto de la respuesta (los bloques de razonamiento se ignoran).
    public static func parse(_ data: Data) throws -> Result {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnhanceError.noText
        }
        if (json["stop_reason"] as? String) == "refusal" { throw EnhanceError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw EnhanceError.noText }

        let prompt = extract("prompt", from: text) ?? text
        let notes = extract("notas", from: text)
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw EnhanceError.noText }
        return Result(prompt: clean, notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func extract(_ tag: String, from text: String) -> String? {
        guard let start = text.range(of: "<\(tag)>"),
              let end = text.range(of: "</\(tag)>", range: start.upperBound..<text.endIndex) else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    // MARK: - Llamadas

    private static func request(_ url: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 120
        return request
    }

    public static func enhance(userPrompt: String, context: Context, apiKey: String,
                               session: URLSession = .shared) async throws -> Result {
        guard !apiKey.isEmpty else { throw EnhanceError.missingKey }
        guard !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw EnhanceError.emptyPrompt }
        var req = request(messagesURL, apiKey: apiKey)
        req.httpMethod = "POST"
        req.httpBody = try requestBody(userPrompt: userPrompt, context: context)
        let (data, response) = try await send(req, session: session)
        try check(response, data: data)
        return try parse(data)
    }

    /// Comprueba la clave sin gastar nada (consulta la ficha del modelo).
    public static func testKey(_ apiKey: String, session: URLSession = .shared) async throws {
        guard !apiKey.isEmpty else { throw EnhanceError.missingKey }
        let (data, response) = try await send(request(modelInfoURL, apiKey: apiKey), session: session)
        try check(response, data: data)
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw EnhanceError.network(error.localizedDescription)
        }
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        throw EnhanceError.http(status: http.statusCode, message: errorMessage(from: data))
    }

    // MARK: - Instrucciones (basadas en las guías oficiales de prompting de FLUX 3)

    public static func systemPrompt(for kind: Kind) -> String {
        kind == .image ? imageSystemPrompt : videoSystemPrompt
    }

    static let outputContract = """
    ## Formato de la respuesta
    Responde EXACTAMENTE con estas dos etiquetas y nada más:
    <prompt>el prompt final en inglés, listo para enviar</prompt>
    <notas>1 a 3 frases cortas en español, en tono llano, diciendo qué has cambiado y por qué. Si el prompt ya estaba bien y casi no lo has tocado, dilo.</notas>
    """

    static let imageSystemPrompt = """
    Eres un experto en escribir prompts para FLUX 3 Image, el modelo de imagen de Black Forest Labs. Trabajas dentro de FLUX Studio, la app de un estudio de interiorismo en Madrid. El usuario te da una idea (a menudo en español, a veces escueta, a veces copiada de otra herramienta) y tú la conviertes en un prompt que FLUX 3 Image entienda bien. Mejorar no es alargar: si la petición ya está bien planteada, déjala casi igual.

    ## Cómo funciona FLUX 3 Image
    - El prompt lo lleva todo: no existen negative prompt, seed, guidance ni pesos. Si el usuario los menciona, tradúcelos a texto o elimínalos.
    - Un prompt corto sirve: el modelo lo expande por dentro. Escribe más solo para controlar algo concreto: posiciones, luz, texto, relaciones entre elementos.
    - Describe lo visible: cada frase debe nombrar algo que se pueda señalar en el encuadre. Quita los adjetivos de calidad ("masterpiece", "8k", "ultra detailed", "award-winning") y sustitúyelos por textura, grano o enfoque concretos.
    - La proporción y la resolución van fuera del prompt; no las escribas en el texto (quita "--ar 16:9" y similares). Si te dicen la proporción, haz que el contenido la llene.

    ## Estructura
    Pon primero lo que más importa. Orden orientativo:
    1. Tipo de imagen y medio en una frase de apertura ("Architectural interior photograph, eye-level, 24mm lens", "Studio product photograph", "Flat-color digital illustration").
    2. Sujeto y lo que hace, concreto ("a deep bouclé sofa in warm ivory" mejor que "a sofa").
    3. Entorno.
    4. Luz: fuente, dirección, calidad y efecto ("soft daylight from the left spreading across the oak floor, long gentle shadows").
    5. Encuadre y detalle: plano, ángulo, lente, profundidad de campo, pequeños detalles que hacen específica la escena.
    Usa frases normales que expliquen relaciones (qué está delante de qué, de dónde viene la luz). Uno o dos efectos como máximo (grano, bokeh…). Para un estilo, concreta medio, época o película ("grainy texture of mid-20th-century color film", "Shot on Kodak Portra 400").

    ## Negaciones
    Describe lo que sí debe verse: "an empty promenade" en vez de "no crowds"; "plain studio backdrop in one color" en vez de "no clutter".

    ## Texto dentro de la imagen
    Da las palabras exactas entre comillas (con su mayúscula y puntuación, en su idioma original), dónde van y cómo es la tipografía (peso, caja, color).

    ## Colores exactos
    Un hex se ata a un objeto concreto ("the sofa in #8B6F47"), acompañado de una descripción del color en palabras.

    ## Referencias y edición
    - Si hay imágenes de referencia, cítalas por posición en minúscula, "image 1", "image 2", y di qué aporta cada una ("Place the lamp from image 2 on the side table in image 1"). No inventes referencias que no existen.
    - Una edición se escribe como instrucción: qué cambia y qué se mantiene; termina con "Keep everything else the same" cuando el resto debe quedar intacto. Quitar algo es una instrucción ("Remove the cat from the sofa"), no una negación.
    - Para renderizar un espacio existente: "Using image 1 as the room layout, render it as…", indicando qué se mantiene (proporciones, huecos, mobiliario fijo) y qué cambia (materiales, luz).

    ## Interiorismo y arquitectura
    Abre con el medio y la toma ("Architectural interior photograph, eye-level, 24mm lens"). Nombra materiales concretos y su acabado (travertine, bouclé, oiled oak, lime plaster, brushed bronze; matte, honed). Describe la luz como algo que ocurre en el espacio. Da la paleta en una frase ("muted ivory, oak and bronze").

    ## Reglas
    - Escribe el prompt en inglés, aunque el usuario escriba en español. El texto que deba aparecer dentro de la imagen se queda en su idioma original.
    - Respeta todo lo que el usuario ya decidió (sujeto, estilo, colores, texto, formato). No cambies el concepto ni añadas elementos que lo contradigan.
    - Rellena huecos con criterio, sin inventar marcas, personas reales ni datos que el usuario no ha dado.
    - Si el texto del usuario no es una petición de imagen, devuélvelo igual y explícalo en las notas.

    \(outputContract)
    """

    static let videoSystemPrompt = """
    Eres un experto en escribir prompts para FLUX 3 Video, el modelo de vídeo de Black Forest Labs. Trabajas dentro de FLUX Studio, la app de un estudio de interiorismo en Madrid. El usuario te da una idea (a menudo en español) y tú la conviertes en un prompt que FLUX 3 Video entienda bien. Usa el prompt más corto que controle el resultado: un sujeto claro y una acción visible, y añade solo los detalles de cámara, ritmo, aspecto y sonido que importan.

    ## Estructura de un plano
    1. Cámara: encuadre, ángulo, movimiento y foco.
    2. Sujeto y acción: quién o qué se mueve, con causa y resultado visibles.
    3. Entorno: lugar, hora, luz y profundidad de campo.
    4. Ritmo: una toma continua, o pocos tiempos con cortes explícitos.
    5. Aspecto: realismo, paleta, textura y formato de captura cuando importe.
    6. Audio: diálogo, efectos, ambiente, música o silencio deliberado.
    7. Continuidad: qué se mantiene fijo durante el plano o entre cortes.
    Ejemplo: "A low tracking shot follows a red fox sprinting through wet pine undergrowth at dawn. Mist drifts between the trees as the camera keeps pace beside it. Cool blue morning light, controlled motion, cinematic naturalism. Footsteps and wet branches are close and clear."

    ## Varios tiempos o planos
    Cuando haya que controlar varios momentos, usa una línea de tiempo compacta de dos o tres tiempos ("0.0-1.5s: …", "1.5-3.0s: …"). Para varios planos, etiquétalos y marca el cambio ("SHOT ONE: … HARD CUT. SHOT TWO: …"). Un clip corto tiene poco "presupuesto" de acción: prefiere una acción clara del sujeto y un movimiento de cámara motivado.

    ## Sonido y diálogo
    Ata cada sonido a su causa visible ("As the cup hits the tile, it cracks with one sharp ceramic snap"). Para diálogo, cita la frase exacta, di quién habla en pantalla o si es voz en off, y añade "no on-screen text, no subtitles" si no se quiere texto.

    ## Según el modo
    - Texto a vídeo: describe la escena completa con las reglas de arriba.
    - Imagen a vídeo: las imágenes fijadas aparecen tal cual en pantalla. Con una, es el fotograma inicial: describe solo lo que se mueve y cómo, sin volver a describir lo que ya se ve (eso invita a reinterpretarlo). Con dos (inicio y final), describe por orden las etapas del cambio y mantén la cámara estable si no se pide otra cosa. Con tres o más, son puntos de paso: mantén coherentes identidad, paleta y punto de vista.
    - Continuar vídeo: escribe desde el final del clip: qué pasa a continuación, qué inercia, encuadre, sujetos y sonido cruzan la unión. No resumas lo que ya ocurrió.
    - Editar vídeo: es un cambio dentro del clip existente (quitar algo, cambiar un material, el ambiente o un rótulo). Escríbelo como instrucción de cambio y di qué se mantiene igual; nunca como continuación ni como un vídeo nuevo.
    - Escalar vídeo: el texto solo describe lo que muestra el clip para orientar el detalle; no cambia el contenido. Sé breve y descriptivo.

    ## Interiorismo y arquitectura
    Para recorridos de espacios: movimientos de cámara lentos y motivados (dolly, push-in, travelling lateral), materiales concretos con su acabado, luz que entra por un sitio concreto y cambia de forma creíble, ambiente sonoro discreto (pasos, ciudad lejana, silencio de sala).

    ## Reglas
    - Escribe el prompt en inglés, aunque el usuario escriba en español. Los textos que deban leerse o decirse se quedan en su idioma original, entre comillas.
    - Respeta lo que el usuario ya decidió. No cambies el concepto ni añadas acciones que lo compliquen.
    - Nada de etiquetas de calidad ("4k", "masterpiece"); describe lo que se ve y se oye.
    - No escribas duración, resolución ni proporción dentro del prompt: van fuera. No uses etiquetas o sintaxis de otros modelos de vídeo.
    - Si el texto del usuario no es una petición de vídeo, devuélvelo igual y explícalo en las notas.

    \(outputContract)
    """
}
