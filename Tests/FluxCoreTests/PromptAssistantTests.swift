import XCTest
@testable import FluxCore

final class PromptAssistantTests: XCTestCase {
    func testSegmentsSplitTextAndPrompts() {
        let text = """
        Lo que delata la IA: luz plana y madera sin veta.

        <prompt target="edit" images="#2, #3" aspect_ratio="auto" resolution="2k">
        Edit image 1 so it looks like a real photograph. Keep everything else the same.
        </prompt>

        He bajado la saturación.
        """
        let segments = PromptAssistant.segments(text)
        XCTAssertEqual(segments.count, 3)
        guard case .text(let first) = segments[0], case .prompt(let s) = segments[1], case .text(let last) = segments[2] else {
            return XCTFail("Segmentos inesperados: \(segments)")
        }
        XCTAssertTrue(first.hasPrefix("Lo que delata"))
        XCTAssertEqual(last, "He bajado la saturación.")
        XCTAssertEqual(s.target, .edit)
        XCTAssertEqual(s.images, [2, 3])
        XCTAssertEqual(s.aspectRatio, "auto")
        XCTAssertEqual(s.resolution, "2k")
        XCTAssertEqual(s.prompt, "Edit image 1 so it looks like a real photograph. Keep everything else the same.")
    }

    func testGenerateWithoutImagesAndUnclosedTag() {
        let s = PromptAssistant.suggestions(in: "<prompt target='generate' images=\"\">A room.</prompt> y <prompt target=\"edit\">sin cerrar")
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.first?.target, .generate)
        XCTAssertEqual(s.first?.images, [])
        XCTAssertNil(s.first?.aspectRatio)
    }

    func testRequestBodyShape() throws {
        let a = PromptAssistant.Attachment(number: 1, fileURL: URL(fileURLWithPath: "/tmp/bar.jpg"), role: .target,
                                           pixelWidth: 1024, pixelHeight: 1024)
        let reply: JSONValue = .array([
            .object(["type": .string("thinking"), "thinking": .string(""), "signature": .string("abc")]),
            .object(["type": .string("text"), "text": .string("Hola")]),
        ])
        let turns = [
            PromptAssistant.Turn(role: .user, text: "Quita el aspecto de IA", attachments: [a]),
            PromptAssistant.Turn(role: .assistant, text: "Hola", rawContent: reply),
            PromptAssistant.Turn(role: .user, text: "Más sutil"),
        ]
        let data = try PromptAssistant.requestBody(turns: turns, model: .sonnet, system: "GUIA") { _ in
            PromptAssistant.EncodedImage(mediaType: "image/jpeg", base64: "QUJD")
        }
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(json["model"]?.stringValue, "claude-sonnet-5-5")
        XCTAssertEqual(json["thinking"]?["type"]?.stringValue, "adaptive")
        XCTAssertEqual(json["system"].flatMap { if case .array(let a) = $0 { return a.first } else { return nil } }?["text"]?.stringValue, "GUIA")
        guard case .array(let messages)? = json["messages"] else { return XCTFail("Sin mensajes") }
        XCTAssertEqual(messages.count, 3)
        // Primer mensaje: etiqueta, imagen y texto.
        guard case .array(let first)? = messages[0]["content"] else { return XCTFail("Sin contenido") }
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first[1]["type"]?.stringValue, "image")
        XCTAssertEqual(first[1]["source"]?["media_type"]?.stringValue, "image/jpeg")
        XCTAssertTrue(first[0]["text"]?.stringValue?.contains("#1") ?? false)
        // La respuesta anterior se reenvía tal cual (con su bloque de razonamiento).
        XCTAssertEqual(messages[1]["content"], reply)
        // Los números se envían como enteros.
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"max_tokens\":16000"))
    }

    func testParseReply() throws {
        let data = Data(#"{"model":"claude-sonnet-5-5","stop_reason":"end_turn","content":[{"type":"thinking","thinking":"","signature":"x"},{"type":"text","text":"Hola"}]}"#.utf8)
        let reply = try PromptAssistant.parseReply(data)
        XCTAssertEqual(reply.text, "Hola")
        XCTAssertEqual(reply.model, "claude-sonnet-5-5")
        XCTAssertFalse(reply.truncated)

        let refusal = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        XCTAssertThrowsError(try PromptAssistant.parseReply(refusal))
    }
}
