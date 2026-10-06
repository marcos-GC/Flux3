import Foundation

/// Cliente de la API de Black Forest Labs.
/// Un método por endpoint (en extensiones) y un único mecanismo de polling.
public final class BFLClient: @unchecked Sendable {
    public let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, region: APIRegion, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = region.baseURL
        self.session = session
    }

    // MARK: - Envío

    /// POST a un endpoint. Devuelve `{ id, polling_url, cost, … }`.
    public func submit<Body: Encodable>(_ endpoint: BFLEndpoint, body: Body) async throws -> SubmitResponse {
        guard !apiKey.isEmpty else { throw BFLError.missingAPIKey }
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint.path))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 300 // los envíos con base64 pueden pesar

        let (data, response) = try await perform(request)
        try Self.validate(response, data: data, phase: .submit)
        do {
            return try JSONDecoder().decode(SubmitResponse.self, from: data)
        } catch {
            throw BFLError.invalidResponse(String(data: data, encoding: .utf8) ?? "sin cuerpo")
        }
    }

    // MARK: - Polling

    /// Consulta la `polling_url` devuelta (sin reescribir el host) hasta un estado final.
    /// Se cancela al cancelar la `Task` que lo llama.
    public func poll(
        _ pollingURL: URL,
        interval: TimeInterval,
        timeout: TimeInterval,
        onUpdate: @escaping @Sendable (PollResponse) async -> Void
    ) async throws -> PollResponse {
        let start = Date()
        var networkFailures = 0
        var waitSeconds = interval

        while true {
            try Task.checkCancellation()
            if Date().timeIntervalSince(start) > timeout {
                throw BFLError.timeout(minutes: Int(timeout / 60))
            }

            var request = URLRequest(url: pollingURL)
            request.setValue(apiKey, forHTTPHeaderField: "x-key")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 60

            do {
                let (data, response) = try await session.data(for: request)
                networkFailures = 0
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 429 || code == 502 || code == 503 || code == 504 {
                    // La tarea sigue viva: esperar más y volver a consultar. Nunca reenviar.
                    waitSeconds = min(waitSeconds * 2, 30)
                    try await Self.sleep(waitSeconds)
                    continue
                }
                try Self.validate(response, data: data, phase: .poll)
                let poll: PollResponse
                do {
                    poll = try JSONDecoder().decode(PollResponse.self, from: data)
                } catch {
                    throw BFLError.invalidResponse(String(data: data, encoding: .utf8) ?? "sin cuerpo")
                }
                await onUpdate(poll)
                switch poll.status.kind {
                case .success:
                    return poll
                case .failure:
                    throw BFLError.taskFailed(status: poll.status, detail: poll.details?.readableText)
                case .running:
                    waitSeconds = interval
                }
            } catch let error as URLError where error.code != .cancelled {
                // Cortes de red puntuales: reintentar unas cuantas veces.
                networkFailures += 1
                if networkFailures >= 6 { throw BFLError.network(error.localizedDescription) }
                waitSeconds = min(waitSeconds * 2, 30)
            }
            try await Self.sleep(waitSeconds)
        }
    }

    /// Envía y espera el resultado en una sola llamada.
    public func run<Body: Encodable>(
        _ endpoint: BFLEndpoint,
        body: Body,
        onSubmitted: @escaping @Sendable (SubmitResponse) async -> Void,
        onUpdate: @escaping @Sendable (PollResponse) async -> Void
    ) async throws -> (SubmitResponse, PollResponse) {
        let submitted = try await submit(endpoint, body: body)
        await onSubmitted(submitted)
        guard let url = URL(string: submitted.pollingURL) else {
            throw BFLError.invalidResponse("polling_url no válida")
        }
        let final = try await poll(url, interval: endpoint.pollInterval, timeout: endpoint.pollTimeout, onUpdate: onUpdate)
        return (submitted, final)
    }

    // MARK: - Descarga

    /// Descarga un resultado. Las URLs firmadas no necesitan (ni deben recibir) la API key.
    public func download(_ url: URL) async throws -> (data: Data, mimeType: String?) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 600
        let (data, response) = try await perform(request)
        try Self.validate(response, data: data, phase: .download)
        return (data, response.mimeType)
    }

    // MARK: - Cuenta

    /// Saldo de créditos. Sirve también para "Probar conexión" sin gastar nada.
    public func credits() async throws -> Double? {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/credits"))
        request.setValue(apiKey, forHTTPHeaderField: "x-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await perform(request)
        try Self.validate(response, data: data, phase: .other)
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        return json?["credits"]?.numberValue
    }

    // MARK: - Utilidades

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw BFLError.network(error.localizedDescription)
        }
    }

    static func validate(_ response: URLResponse, data: Data, phase: BFLError.Phase) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw BFLError.http(status: http.statusCode, detail: errorDetail(from: data), phase: phase)
        }
    }

    /// Extrae el texto útil de un cuerpo de error (`{"detail": …}` u otros).
    public static func errorDetail(from data: Data) -> String? {
        if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let text = json.readableText
            return text.isEmpty ? nil : String(text.prefix(500))
        }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : String(text.prefix(500))
    }

    private static func sleep(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
