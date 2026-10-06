import XCTest
@testable import FluxCore

final class RequestEncodingTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testDefaultsAreOmitted() throws {
        let body = try json(Flux3ImageRequest(prompt: "una silla"))
        XCTAssertEqual(body["prompt"] as? String, "una silla")
        XCTAssertEqual(body["resolution"] as? String, "1k")
        XCTAssertEqual(body["safety_tolerance"] as? Int, 2)
        XCTAssertNil(body["aspect_ratio"], "auto no se envía")
        XCTAssertNil(body["grounding"], "true es el valor por defecto")
        XCTAssertNil(body["images"])
        XCTAssertNil(body["seed"], "FLUX 3 Image no admite seed")
    }

    func testExplicitValues() throws {
        let body = try json(Flux3ImageRequest(
            prompt: "p", images: ["https://a/b.jpg"], aspectRatio: "2:3",
            resolution: "2k", safetyTolerance: 0, grounding: false
        ))
        XCTAssertEqual(body["aspect_ratio"] as? String, "2:3")
        XCTAssertEqual(body["resolution"] as? String, "2k")
        XCTAssertEqual(body["safety_tolerance"] as? Int, 0)
        XCTAssertEqual(body["grounding"] as? Bool, false)
        XCTAssertEqual(body["images"] as? [String], ["https://a/b.jpg"])
    }

    func testMaxTenImages() throws {
        let request = Flux3ImageRequest(prompt: "p", images: Array(repeating: "x", count: 12))
        XCTAssertEqual(request.images?.count, 10)
    }

    func testLargeStringsAreStrippedForMetadata() throws {
        let big = String(repeating: "A", count: 5000)
        let value = try JSONValue(encoding: Flux3ImageRequest(prompt: "p", images: [big, "https://x/y.jpg"]))
        let stripped = value.strippingLargeStrings()
        guard case .array(let images)? = stripped["images"] else { return XCTFail("sin images") }
        XCTAssertTrue(images[0].stringValue?.hasPrefix("<archivo") ?? false)
        XCTAssertEqual(images[1].stringValue, "https://x/y.jpg")
    }
}
