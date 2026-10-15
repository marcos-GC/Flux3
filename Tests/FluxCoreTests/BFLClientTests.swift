import XCTest
@testable import FluxCore

/// Servidor falso: responde a cada petición con lo que diga `handler`.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler, let url = request.url else { return }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Registro seguro entre hilos de las peticiones recibidas.
final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URLRequest] = []

    func append(_ r: URLRequest) { lock.lock(); items.append(r); lock.unlock() }
    var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return items }
}

final class BFLClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
    }

    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testPollsUntilReadyUsingTheReturnedURLAndKey() async throws {
        let log = RequestLog()
        let statuses = ["Pending", "Reasoning", "Generating"]
        MockURLProtocol.handler = { request in
            log.append(request)
            let n = log.all.count - 1
            if n < statuses.count {
                return (200, Data(#"{"id":"t1","status":"\#(statuses[n])"}"#.utf8))
            }
            return (200, Data(#"{"id":"t1","status":"Ready","result":{"sample":"https://cdn.example/x.jpg","prompt":"expanded"}}"#.utf8))
        }
        let client = BFLClient(apiKey: "KEY", region: .eu, session: session)
        let pollURL = URL(string: "https://api.us2.bfl.ai/v1/get_result?id=t1")!
        let seen = RequestLog()
        let final = try await client.poll(pollURL, interval: 0.01, timeout: 10) { poll in
            seen.append(URLRequest(url: URL(string: "status://\(poll.status.rawValue.replacingOccurrences(of: " ", with: "_"))")!))
        }
        XCTAssertEqual(final.status, .ready)
        XCTAssertEqual(final.result?.prompt, "expanded")
        XCTAssertEqual(log.all.count, 4)
        // Se consulta la polling_url devuelta, sin reescribir el host, y con la cabecera x-key.
        XCTAssertTrue(log.all.allSatisfy { $0.url == pollURL })
        XCTAssertTrue(log.all.allSatisfy { $0.value(forHTTPHeaderField: "x-key") == "KEY" })
        XCTAssertEqual(seen.all.compactMap { $0.url?.host }, ["Pending", "Reasoning", "Generating", "Ready"])
    }

    func testModerationStopsWithSpanishError() async {
        MockURLProtocol.handler = { _ in (200, Data(#"{"status":"Content Moderated"}"#.utf8)) }
        let client = BFLClient(apiKey: "KEY", region: .eu, session: session)
        do {
            _ = try await client.poll(URL(string: "https://api.eu.bfl.ai/v1/get_result?id=x")!, interval: 0.01, timeout: 10) { _ in }
            XCTFail("debería fallar")
        } catch let error as BFLError {
            XCTAssertEqual(error, .taskFailed(status: .contentModerated, detail: nil))
            XCTAssertTrue(error.errorDescription!.hasPrefix("Moderado"))
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    func testRateLimitWhilePollingKeepsWaiting() async throws {
        let log = RequestLog()
        MockURLProtocol.handler = { request in
            log.append(request)
            return log.all.count == 1
                ? (429, Data(#"{"detail":"slow down"}"#.utf8))
                : (200, Data(#"{"status":"Ready","result":{"sample":"https://cdn.example/x.jpg"}}"#.utf8))
        }
        let client = BFLClient(apiKey: "KEY", region: .eu, session: session)
        let final = try await client.poll(URL(string: "https://api.eu.bfl.ai/v1/get_result?id=x")!, interval: 0.01, timeout: 10) { _ in }
        XCTAssertEqual(final.status, .ready)
        XCTAssertEqual(log.all.count, 2)
    }

    func testSubmitSendsJSONToRegionAndMapsErrors() async throws {
        let log = RequestLog()
        MockURLProtocol.handler = { request in
            log.append(request)
            return (402, Data(#"{"detail":"Insufficient credits"}"#.utf8))
        }
        let client = BFLClient(apiKey: "KEY", region: .eu, session: session)
        do {
            _ = try await client.submit(.flux3Image, body: Flux3ImageRequest(prompt: "p"))
            XCTFail("debería fallar")
        } catch let error as BFLError {
            guard case .http(let status, _, let phase) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(status, 402)
            XCTAssertEqual(phase, .submit)
            XCTAssertTrue(error.errorDescription!.contains("créditos"))
        }
        let request = try XCTUnwrap(log.all.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.eu.bfl.ai/v1/flux-3-image")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-key"), "KEY")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTimeout() async {
        MockURLProtocol.handler = { _ in (200, Data(#"{"status":"Pending"}"#.utf8)) }
        let client = BFLClient(apiKey: "KEY", region: .eu, session: session)
        do {
            _ = try await client.poll(URL(string: "https://api.eu.bfl.ai/v1/get_result?id=x")!, interval: 0.02, timeout: 0.1) { _ in }
            XCTFail("debería agotar el tiempo")
        } catch let error as BFLError {
            if case .timeout = error {} else { XCTFail("\(error)") }
        } catch {
            XCTFail("error inesperado: \(error)")
        }
    }

    func testCancellationStopsPolling() async {
        MockURLProtocol.handler = { _ in (200, Data(#"{"status":"Pending"}"#.utf8)) }
        let client = BFLClient(apiKey: "KEY", region: .eu, session: session)
        let task = Task {
            try await client.poll(URL(string: "https://api.eu.bfl.ai/v1/get_result?id=x")!, interval: 0.05, timeout: 60) { _ in }
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let result = await task.result
        switch result {
        case .success: XCTFail("debería cancelarse")
        case .failure(let error): XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled, "\(error)")
        }
    }
}
