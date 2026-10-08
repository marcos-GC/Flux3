import XCTest
@testable import FluxCore

final class VideoRequestTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    func testTextToVideoDefaultsOmitted() throws {
        let body = try json(Flux3VideoRequest(mode: .t2v, prompt: "a slow dolly into a living room"))
        XCTAssertEqual(body["mode"] as? String, "t2v")
        XCTAssertEqual(body["resolution"] as? String, "hd")
        XCTAssertEqual(body["safety_tolerance"] as? Int, 2)
        XCTAssertNil(body["aspect_ratio"], "auto no se envía")
        XCTAssertNil(body["duration"], "auto no se envía")
        XCTAssertNil(body["generate_audio"], "true es el valor por defecto")
        XCTAssertNil(body["draft"])
        XCTAssertNil(body["keyframes"])
    }

    func testImageToVideoWithoutTimestamps() throws {
        let req = Flux3VideoRequest(mode: .i2v, prompt: "p",
                                    keyframes: [.init(image: "A"), .init(image: "B")],
                                    aspectRatio: "16:9", duration: 25, resolution: "fhd",
                                    generateAudio: false, safetyTolerance: 9)
        let body = try json(req)
        XCTAssertEqual(body["keyframes"] as? [String], ["A", "B"])
        XCTAssertEqual(body["duration"] as? Int, 20, "máximo 20 s")
        XCTAssertEqual(body["aspect_ratio"] as? String, "16:9")
        XCTAssertEqual(body["generate_audio"] as? Bool, false)
        XCTAssertEqual(body["safety_tolerance"] as? Int, 4, "vídeo admite hasta 4")
        XCTAssertNil(req.validationError())
    }

    func testImageToVideoWithTimestamps() throws {
        let req = Flux3VideoRequest(mode: .i2v, prompt: "p",
                                    keyframes: [.init(image: "A", seconds: 0), .init(image: "B", seconds: 2.5),
                                                .init(image: "C", seconds: 8)],
                                    duration: 10)
        let frames = try XCTUnwrap(try json(req)["keyframes"] as? [[Any]])
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0][0] as? Int, 0)
        XCTAssertEqual(frames[0][1] as? String, "A")
        XCTAssertEqual(frames[1][0] as? Double, 2.5)
        XCTAssertNil(req.validationError())
    }

    func testValidation() {
        XCTAssertNotNil(Flux3VideoRequest(mode: .i2v, prompt: "p").validationError(), "sin fotogramas")
        XCTAssertNotNil(Flux3VideoRequest(mode: .i2v, prompt: "p",
                                          keyframes: [.init(image: "A", seconds: 1), .init(image: "B")]).validationError(),
                        "todos con tiempo o ninguno")
        XCTAssertNotNil(Flux3VideoRequest(mode: .i2v, prompt: "p",
                                          keyframes: [.init(image: "A"), .init(image: "B"), .init(image: "C")]).validationError(),
                        "3+ sin tiempos necesitan duración")
        XCTAssertNil(Flux3VideoRequest(mode: .i2v, prompt: "p",
                                       keyframes: [.init(image: "A"), .init(image: "B"), .init(image: "C")],
                                       duration: 12).validationError())
        XCTAssertNotNil(Flux3VideoRequest(mode: .i2v, prompt: "p",
                                          keyframes: [.init(image: "A", seconds: 5), .init(image: "B", seconds: 2)]).validationError(),
                        "orden creciente")
        XCTAssertNotNil(Flux3VideoRequest(mode: .t2v, prompt: "  ").validationError())
        XCTAssertNotNil(Flux3VideoRequest(mode: .v2v, prompt: "p").validationError())
    }

    func testDraftForcesHDAndEnhanceIsMinimal() throws {
        let draft = try json(Flux3VideoRequest(mode: .t2v, prompt: "p", resolution: "fhd", draft: true))
        XCTAssertEqual(draft["draft"] as? Bool, true)
        XCTAssertEqual(draft["resolution"] as? String, "hd")

        let enhance = try json(Flux3VideoRequest.draftEnhance(cache: "https://cache/x"))
        XCTAssertEqual(Set(enhance.keys), ["mode", "draft_cache"])
        XCTAssertEqual(enhance["mode"] as? String, "draft_enhance")

        let enhanceHD = try json(Flux3VideoRequest.draftEnhance(cache: "c", resolution: "hd"))
        XCTAssertEqual(enhanceHD["resolution"] as? String, "hd")
    }

    func testContinueVideo() throws {
        let body = try json(Flux3VideoRequest(mode: .v2v, prompt: "the camera keeps moving", startVideo: "MP4"))
        XCTAssertEqual(body["start_video"] as? String, "MP4")
        XCTAssertNil(body["keyframes"])
    }

    func testEditAndUpscale() throws {
        let edit = try json(VideoEditRequest(video: "V", prompt: String(repeating: "a", count: 5000), safetyTolerance: 5))
        XCTAssertEqual((edit["prompt"] as? String)?.count, 4096)
        XCTAssertEqual(edit["safety_tolerance"] as? Int, 4)

        let up = try json(VideoUpscaleRequest(inputVideo: "V", creativity: 7, upscaleFactor: 4))
        XCTAssertEqual(up["input_video"] as? String, "V")
        XCTAssertEqual(up["creativity"] as? Int, 1)
        XCTAssertEqual(up["upscale_factor"] as? Double, 3)
        XCTAssertNil(up["prompt"])
    }
}
