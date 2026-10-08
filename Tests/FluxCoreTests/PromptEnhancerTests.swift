import XCTest
@testable import FluxCore

final class PromptEnhancerTests: XCTestCase {
    func testRequestBody() throws {
        let data = try PromptEnhancer.requestBody(
            userPrompt: "un salón luminoso", context: .init(kind: .image, referenceCount: 2, aspectRatio: "3:2")
        )
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "claude-haiku-5-5")
        XCTAssertNotNil(json["max_tokens"] as? Int)
        XCTAssertEqual((json["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNil(json["temperature"], "Haiku 5.5 rechaza parámetros de muestreo no por defecto")
        XCTAssertNil(json["thinking"])

        let system = try XCTUnwrap(json["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 1)
        XCTAssertEqual((system[0]["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
        XCTAssertTrue((system[0]["text"] as? String)?.contains("FLUX 3 Image") ?? false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(content.contains("image 1, image 2"))
        XCTAssertTrue(content.contains("<proporcion>3:2</proporcion>"))
        XCTAssertTrue(content.contains("un salón luminoso"))
    }

    func testVideoSystemPrompt() throws {
        let data = try PromptEnhancer.requestBody(
            userPrompt: "recorrido por la cocina", context: .init(kind: .video, videoMode: "Imagen a vídeo", keyframeCount: 1)
        )
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let system = try XCTUnwrap((json["system"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertTrue(system.contains("FLUX 3 Video"))
        let content = try XCTUnwrap((json["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(content.contains("<modo>Imagen a vídeo</modo>"))
        XCTAssertTrue(content.contains("<fotogramas_clave>1"))
    }

    func testParseIgnoresThinkingAndExtractsTags() throws {
        let response = #"""
        {"id":"msg_1","type":"message","role":"assistant","model":"claude-haiku-5-5","stop_reason":"end_turn",
         "content":[
           {"type":"thinking","thinking":"","signature":"abc"},
           {"type":"text","text":"<prompt>Architectural interior photograph, eye-level, 24mm lens.</prompt>\n<notas>He concretado la luz.</notas>"}
         ],
         "usage":{"input_tokens":10,"output_tokens":20}}
        """#
        let result = try PromptEnhancer.parse(Data(response.utf8))
        XCTAssertEqual(result.prompt, "Architectural interior photograph, eye-level, 24mm lens.")
        XCTAssertEqual(result.notes, "He concretado la luz.")
    }

    func testParseWithoutTagsUsesWholeText() throws {
        let response = #"{"stop_reason":"end_turn","content":[{"type":"text","text":"  A red chair.  "}]}"#
        let result = try PromptEnhancer.parse(Data(response.utf8))
        XCTAssertEqual(result.prompt, "A red chair.")
        XCTAssertNil(result.notes)
    }

    func testRefusalAndEmpty() {
        let refusal = #"{"stop_reason":"refusal","content":[]}"#
        XCTAssertThrowsError(try PromptEnhancer.parse(Data(refusal.utf8))) {
            XCTAssertEqual($0 as? PromptEnhancer.EnhanceError, .refused)
        }
        let empty = #"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""}]}"#
        XCTAssertThrowsError(try PromptEnhancer.parse(Data(empty.utf8))) {
            XCTAssertEqual($0 as? PromptEnhancer.EnhanceError, .noText)
        }
    }

    func testErrorsInSpanish() {
        XCTAssertTrue(PromptEnhancer.EnhanceError.http(status: 401, message: nil).errorDescription!.contains("no es válida"))
        XCTAssertTrue(PromptEnhancer.EnhanceError.http(status: 529, message: nil).errorDescription!.contains("saturados"))
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad"}}"#.utf8)
        XCTAssertEqual(PromptEnhancer.errorMessage(from: body), "bad")
    }
}
