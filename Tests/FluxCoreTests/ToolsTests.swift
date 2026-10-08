import CoreGraphics
import ImageIO
import XCTest
@testable import FluxCore

final class ToolsTests: XCTestCase {
    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }

    // MARK: Máscara de Borrar

    func testMaskPaintsWhiteWhereBrushed() {
        let stroke = MaskStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1, erases: false)
        let px = MaskRenderer.renderBitmap(strokes: [stroke], inverted: false, width: 100, height: 50)
        XCTAssertEqual(px.count, 100 * 50)
        XCTAssertEqual(px[25 * 100 + 50], 255, "centro del trazo = blanco (borrar)")
        XCTAssertEqual(px[0], 0, "esquina = negro (mantener)")
        XCTAssertEqual(Set(px), [0, 255], "solo blanco y negro")
    }

    func testMaskTopIsTop() {
        // Un trazo arriba a la izquierda debe quedar arriba a la izquierda en la máscara.
        let stroke = MaskStroke(points: [CGPoint(x: 0.1, y: 0.1)], radius: 0.05, erases: false)
        let px = MaskRenderer.renderBitmap(strokes: [stroke], inverted: false, width: 100, height: 100)
        XCTAssertEqual(px[10 * 100 + 10], 255)
        XCTAssertEqual(px[90 * 100 + 10], 0)
    }

    func testEraserAndInvert() {
        let paint = MaskStroke(points: [CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)], radius: 0.1, erases: false)
        let rubber = MaskStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.1, erases: true)
        let px = MaskRenderer.renderBitmap(strokes: [paint, rubber], inverted: false, width: 100, height: 100)
        XCTAssertEqual(px[50 * 100 + 25], 255)
        XCTAssertEqual(px[50 * 100 + 50], 0, "la goma quita la máscara")

        let inv = MaskRenderer.renderBitmap(strokes: [paint, rubber], inverted: true, width: 100, height: 100)
        XCTAssertEqual(inv[50 * 100 + 25], 0)
        XCTAssertEqual(inv[50 * 100 + 50], 255)
        XCTAssertEqual(inv[0], 255)
    }

    func testMaskPNGHasImageSize() throws {
        let stroke = MaskStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.2, erases: false)
        let data = try XCTUnwrap(MaskRenderer.pngData(strokes: [stroke], inverted: false, width: 640, height: 427))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 640)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 427)
    }

    func testEmptyMask() {
        XCTAssertTrue(MaskRenderer.isEmpty(strokes: [], inverted: false))
        XCTAssertTrue(MaskRenderer.isEmpty(strokes: [MaskStroke(points: [.zero], radius: 0.1, erases: true)], inverted: false))
        XCTAssertFalse(MaskRenderer.isEmpty(strokes: [], inverted: true))
    }

    // MARK: Outpainting

    func testOutpaintCanvasForRatio() {
        let src = CGSize(width: 800, height: 600) // 4:3
        let square = OutpaintGeometry.canvas(for: src, ratio: 1, expand: 1)
        XCTAssertEqual(square, CGSize(width: 800, height: 800))
        let wide = OutpaintGeometry.canvas(for: src, ratio: 16.0 / 9.0, expand: 1)
        XCTAssertEqual(wide.height, 608) // 600 redondeado a múltiplo de 16
        XCTAssertGreaterThanOrEqual(wide.width / wide.height, 16.0 / 9.0 - 0.02)
        let bigger = OutpaintGeometry.canvas(for: src, ratio: nil, expand: 1.5)
        XCTAssertEqual(bigger, CGSize(width: 1200, height: 912))
    }

    func testOutpaintOffsets() {
        let src = CGSize(width: 400, height: 300)
        let canvas = CGSize(width: 800, height: 600)
        XCTAssertEqual(OutpaintGeometry.centeredOffset(source: src, canvas: canvas), CGPoint(x: 200, y: 150))
        XCTAssertEqual(OutpaintGeometry.clamp(CGPoint(x: -50, y: 500), source: src, canvas: canvas), CGPoint(x: 0, y: 300))
    }

    func testOutpaintRequestEncoding() throws {
        let centered = try json(OutpaintRequest(inputImage: "b64", width: 1024, height: 768, safetyTolerance: 9))
        XCTAssertEqual(centered["input_image"] as? String, "b64")
        XCTAssertEqual(centered["mode"] as? String, "high")
        XCTAssertEqual(centered["safety_tolerance"] as? Int, 5, "Outpainting admite hasta 5")
        XCTAssertNil(centered["reference_offset_x"], "vacío = centrado")
        XCTAssertNil(centered["prompt"])

        let moved = try json(OutpaintRequest(inputImage: "b64", width: 30, height: 2000, prompt: " sea ",
                                             offset: CGPoint(x: 12.4, y: 0), mode: .fast, outputFormat: .png))
        XCTAssertEqual(moved["width"] as? Int, 64, "mínimo 64")
        XCTAssertEqual(moved["reference_offset_x"] as? Int, 12)
        XCTAssertEqual(moved["reference_offset_y"] as? Int, 0)
        XCTAssertEqual(moved["prompt"] as? String, "sea")
        XCTAssertEqual(moved["output_format"] as? String, "png")
    }

    // MARK: Erase, Deblur, VTO

    func testEraseRequest() throws {
        let body = try json(EraseRequest(image: "i", mask: "m", dilatePixels: 40, safetyTolerance: 5))
        XCTAssertEqual(body["dilate_pixels"] as? Int, 25)
        XCTAssertEqual(body["safety_tolerance"] as? Int, 5)
        XCTAssertNil(body["seed"])
    }

    func testDeblurAndTryOnRequests() throws {
        let deblur = try json(DeblurRequest(image: "i", seed: 7))
        XCTAssertEqual(deblur["seed"] as? Int, 7)
        let vto = try json(TryOnRequest(prompt: TryOnRequest.prompt(forGarment: "red hoodie"), person: "p", garment: "g", safetyTolerance: -3))
        XCTAssertEqual(vto["prompt"] as? String, "The person of image 1, maintaining exactly their face and pose, wearing the red hoodie of image 2.")
        XCTAssertEqual(vto["safety_tolerance"] as? Int, 0)
        XCTAssertEqual(vto["output_format"] as? String, "jpeg")
    }
}
