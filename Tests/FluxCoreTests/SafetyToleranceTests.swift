import XCTest
@testable import FluxCore

final class SafetyToleranceTests: XCTestCase {
    func testRangesPerEndpoint() {
        XCTAssertEqual(SafetyTolerance.range(for: .flux3Image), 0...4)
        XCTAssertEqual(SafetyTolerance.range(for: .flux3Video), 0...4)
        XCTAssertEqual(SafetyTolerance.range(for: .videoEdit), 0...4)
        XCTAssertEqual(SafetyTolerance.range(for: .videoUpscale), 0...4)
        XCTAssertEqual(SafetyTolerance.range(for: .outpaint), 0...5)
        XCTAssertEqual(SafetyTolerance.range(for: .erase), 0...5)
        XCTAssertEqual(SafetyTolerance.range(for: .deblur), 0...5)
        XCTAssertEqual(SafetyTolerance.range(for: .vto), 0...5)
    }

    func testClampToMaximumWhenSwitchingMode() {
        XCTAssertEqual(SafetyTolerance.clamp(5, for: .flux3Image), 4)
        XCTAssertEqual(SafetyTolerance.clamp(5, for: .erase), 5)
        XCTAssertEqual(SafetyTolerance.clamp(-1, for: .deblur), 0)
        XCTAssertEqual(SafetyTolerance.clamp(2, for: .flux3Video), 2)
    }

    func testLabels() {
        XCTAssertEqual(SafetyTolerance.label(for: 0, maximum: 4), "Muy estricto")
        XCTAssertEqual(SafetyTolerance.label(for: 2, maximum: 4), "Por defecto")
        XCTAssertEqual(SafetyTolerance.label(for: 4, maximum: 4), "Muy permisivo")
        XCTAssertEqual(SafetyTolerance.label(for: 5, maximum: 5), "Muy permisivo")
        XCTAssertEqual(SafetyTolerance.label(for: 4, maximum: 5), "Bastante permisivo")
    }

    func testRequestClampsSafety() {
        let request = Flux3ImageRequest(prompt: "x", safetyTolerance: 5)
        XCTAssertEqual(request.safetyTolerance, 4)
    }
}
