import XCTest
@testable import FluxCore

final class BFLModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testSubmitResponse() throws {
        let r = try decode(SubmitResponse.self, """
        {"id":"abc","polling_url":"https://api.eu.bfl.ai/v1/get_result?id=abc","cost":4.5,"input_mp":0,"output_mp":1.05}
        """)
        XCTAssertEqual(r.id, "abc")
        XCTAssertEqual(r.pollingURL, "https://api.eu.bfl.ai/v1/get_result?id=abc")
        XCTAssertEqual(r.cost, 4.5)
        XCTAssertEqual(r.outputMP, 1.05)
    }

    func testSubmitResponseWithoutCost() throws {
        let r = try decode(SubmitResponse.self, #"{"id":"a","polling_url":"https://x/y"}"#)
        XCTAssertNil(r.cost)
    }

    func testPollReadyImage() throws {
        let r = try decode(PollResponse.self, """
        {"id":"abc","status":"Ready","result":{"sample":"https://cdn/x.jpg","prompt":"expanded prompt"}}
        """)
        XCTAssertEqual(r.status, .ready)
        XCTAssertEqual(r.status.kind, .success)
        XCTAssertEqual(r.result?.sampleURLs, [URL(string: "https://cdn/x.jpg")!])
        XCTAssertEqual(r.result?.prompt, "expanded prompt")
    }

    func testPollReadyVideoLists() throws {
        let r = try decode(PollResponse.self, """
        {"status":"Ready","result":{"samples":["https://cdn/a.mp4","https://cdn/b.mp4"],"draft_cache":"c1","draft_caches":["c1","c2"]}}
        """)
        XCTAssertEqual(r.result?.sampleURLs.count, 2)
        XCTAssertEqual(r.result?.draftCaches, ["c1", "c2"])
    }

    func testRunningAndFailureStatuses() throws {
        for s in ["Pending", "Reasoning", "Generating", "SomethingNew"] {
            XCTAssertEqual(BFLStatus(rawValue: s).kind, .running, s)
        }
        for s in ["Error", "Request Moderated", "Content Moderated", "Task not found"] {
            XCTAssertEqual(BFLStatus(rawValue: s).kind, .failure, s)
        }
        let r = try decode(PollResponse.self, #"{"status":"Reasoning","result":null}"#)
        XCTAssertEqual(r.status.spanishLabel, "Razonando")
        XCTAssertNil(r.result)
    }
}
