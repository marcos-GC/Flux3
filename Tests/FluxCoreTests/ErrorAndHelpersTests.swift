import XCTest
@testable import FluxCore

final class ErrorAndHelpersTests: XCTestCase {
    func testHTTPErrorsInSpanish() {
        XCTAssertTrue(BFLError.http(status: 401, detail: nil, phase: .submit).errorDescription!.contains("API key"))
        XCTAssertTrue(BFLError.http(status: 402, detail: nil, phase: .submit).errorDescription!.contains("créditos"))
        XCTAssertTrue(BFLError.http(status: 422, detail: "aspect_ratio: invalid", phase: .submit).errorDescription!.contains("aspect_ratio"))
        XCTAssertTrue(BFLError.http(status: 429, detail: nil, phase: .submit).errorDescription!.contains("No se ha creado"))
        XCTAssertTrue(BFLError.http(status: 429, detail: nil, phase: .poll).errorDescription!.contains("sigue en marcha"))
    }

    func testModerationMessage() {
        let text = BFLError.taskFailed(status: .contentModerated, detail: nil).errorDescription!
        XCTAssertTrue(text.hasPrefix("Moderado"))
        XCTAssertTrue(text.contains("tolerancia de seguridad"))
    }

    func testValidationDetailIsReadable() {
        let body = #"{"detail":[{"loc":["body","aspect_ratio"],"msg":"Input should be '1:1'","type":"enum"}]}"#
        XCTAssertEqual(BFLClient.errorDetail(from: Data(body.utf8)), "aspect_ratio: Input should be '1:1'")
    }

    func testFileExtension() {
        XCTAssertEqual(MediaType.fileExtension(mimeType: "image/jpeg", url: nil), "jpg")
        XCTAssertEqual(MediaType.fileExtension(mimeType: "image/png", url: nil), "png")
        XCTAssertEqual(MediaType.fileExtension(mimeType: "video/mp4", url: nil), "mp4")
        XCTAssertEqual(MediaType.fileExtension(mimeType: nil, url: URL(string: "https://x/a.webp?sig=1")), "webp")
        XCTAssertEqual(MediaType.fileExtension(mimeType: "application/octet-stream", url: URL(string: "https://x/a")), "jpg")
    }

    func testAspectRatio() {
        XCTAssertEqual(AspectRatio.value(of: "16:9")!, 16.0 / 9.0, accuracy: 0.0001)
        XCTAssertNil(AspectRatio.value(of: "auto"))
    }

    func testRegions() {
        XCTAssertEqual(APIRegion.eu.baseURL.absoluteString, "https://api.eu.bfl.ai")
        XCTAssertEqual(APIRegion.global.baseURL.appendingPathComponent(BFLEndpoint.flux3Image.path).absoluteString,
                       "https://api.bfl.ai/v1/flux-3-image")
    }
}
