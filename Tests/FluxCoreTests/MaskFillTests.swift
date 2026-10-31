import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FluxCore

final class MaskFillTests: XCTestCase {
    // MARK: Polígono

    func testPolygonFillsInside() {
        // Cuadrado entre 0.2 y 0.6: dentro blanco, fuera negro, con bordes rectos.
        let square = MaskStroke(points: [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.6, y: 0.2),
                                         CGPoint(x: 0.6, y: 0.6), CGPoint(x: 0.2, y: 0.6)],
                                radius: 0, erases: false, isPolygon: true)
        let px = MaskRenderer.renderBitmap(strokes: [square], inverted: false, width: 100, height: 100)
        XCTAssertEqual(px[40 * 100 + 40], 255, "centro del polígono")
        XCTAssertEqual(px[25 * 100 + 55], 255)
        XCTAssertEqual(px[10 * 100 + 40], 0, "encima del polígono")
        XCTAssertEqual(px[40 * 100 + 70], 0, "a la derecha del polígono")
        let box = MaskFill.boundingBox(mask: px, width: 100, height: 100)!
        XCTAssertEqual(box.x, 20, accuracy: 1)
        XCTAssertEqual(box.y, 20, accuracy: 1)
        XCTAssertEqual(box.maxX, 60, accuracy: 1)
        XCTAssertEqual(box.maxY, 60, accuracy: 1)
    }

    func testPolygonTriangleIsNotABox() {
        let triangle = MaskStroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)],
                                  radius: 0, erases: false, isPolygon: true)
        let px = MaskRenderer.renderBitmap(strokes: [triangle], inverted: false, width: 100, height: 100)
        XCTAssertEqual(px[10 * 100 + 10], 255)
        XCTAssertEqual(px[90 * 100 + 90], 0, "la esquina opuesta queda fuera")
    }

    func testPolygonWithTwoPointsMarksNothing() {
        let line = MaskStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)],
                              radius: 0, erases: false, isPolygon: true)
        XCTAssertFalse(line.hasArea)
        XCTAssertTrue(MaskRenderer.isEmpty(strokes: [line], inverted: false))
    }

    func testPolygonCanUnmark() {
        let paint = MaskStroke(points: [CGPoint(x: 0.5, y: 0.5)], radius: 0.4, erases: false)
        let cut = MaskStroke(points: [CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.6, y: 0.4), CGPoint(x: 0.6, y: 0.6)],
                             radius: 0, erases: true, isPolygon: true)
        let px = MaskRenderer.renderBitmap(strokes: [paint, cut], inverted: false, width: 100, height: 100)
        XCTAssertEqual(px[45 * 100 + 55], 0, "dentro del polígono de desmarcar")
        XCTAssertEqual(px[70 * 100 + 50], 255, "resto de la pincelada")
    }

    // MARK: Caja y prompt

    func testBoundingBoxEmpty() {
        XCTAssertNil(MaskFill.boundingBox(mask: [UInt8](repeating: 0, count: 100), width: 10, height: 10))
    }

    func testPaintedBoxScalesToImageAndAddsMargin() {
        let square = MaskStroke(points: [CGPoint(x: 0.25, y: 0.5), CGPoint(x: 0.75, y: 0.5),
                                         CGPoint(x: 0.75, y: 0.75), CGPoint(x: 0.25, y: 0.75)],
                                radius: 0, erases: false, isPolygon: true)
        let box = MaskFill.paintedBox(strokes: [square], inverted: false, imageWidth: 2000, imageHeight: 1000, margin: 0)!
        XCTAssertEqual(box.x, 500, accuracy: 6)
        XCTAssertEqual(box.y, 500, accuracy: 6)
        XCTAssertEqual(box.maxX, 1500, accuracy: 6)
        XCTAssertEqual(box.maxY, 750, accuracy: 6)

        let padded = MaskFill.paintedBox(strokes: [square], inverted: false, imageWidth: 2000, imageHeight: 1000)!
        XCTAssertLessThan(padded.x, box.x)
        XCTAssertGreaterThan(padded.maxX, box.maxX)
        XCTAssertNil(MaskFill.paintedBox(strokes: [], inverted: false, imageWidth: 2000, imageHeight: 1000))
    }

    func testPromptUsesEditRegionFormat() {
        let box = PixelRect(x: 100, y: 100, width: 200, height: 100)
        let prompt = MaskFill.prompt(instruction: "white marble tabletop", box: box, imageWidth: 1000, imageHeight: 1000)
        XCTAssertTrue(prompt.hasPrefix("Edit the first reference image."))
        XCTAssertTrue(prompt.contains("<region_1>"))
        XCTAssertTrue(prompt.contains("\"white marble tabletop\""))
        XCTAssertTrue(prompt.contains("\"src_bbox\":[100,100,200,300]"))
        XCTAssertFalse(prompt.contains("ref_image_1"))

        let withRef = MaskFill.prompt(instruction: "this armchair", box: box, imageWidth: 1000, imageHeight: 1000,
                                      hasReference: true)
        XCTAssertTrue(withRef.contains("<ref_image_1>"))
    }

    // MARK: Borde suavizado

    func testFeatheredAlphaCoversMaskAndFadesOutward() {
        let w = 60, h = 60
        var mask = [UInt8](repeating: 0, count: w * h)
        for y in 20..<40 { for x in 20..<40 { mask[y * w + x] = 255 } }
        let alpha = MaskFill.featheredAlpha(mask: mask, width: w, height: h, grow: 2, feather: 6)
        XCTAssertEqual(alpha[30 * w + 30], 255, "centro")
        XCTAssertEqual(alpha[30 * w + 20], 255, "borde de lo pintado: totalmente cubierto")
        XCTAssertEqual(alpha[30 * w + 18], 255, "dentro de lo agrandado")
        let fade = alpha[30 * w + 15]
        XCTAssertGreaterThan(fade, 0)
        XCTAssertLessThan(fade, 255, "transición suave")
        XCTAssertEqual(alpha[30 * w + 5], 0, "lejos: no se toca")
        XCTAssertEqual(alpha[2 * w + 2], 0)
    }

    func testFeatheredAlphaWithoutFeatherIsHard() {
        let w = 20, h = 20
        var mask = [UInt8](repeating: 0, count: w * h)
        mask[10 * w + 10] = 255
        let alpha = MaskFill.featheredAlpha(mask: mask, width: w, height: h, grow: 0, feather: 0)
        XCTAssertEqual(alpha, mask)
        let grown = MaskFill.featheredAlpha(mask: mask, width: w, height: h, grow: 2, feather: 0)
        XCTAssertEqual(grown[12 * w + 12], 255)
        XCTAssertEqual(grown[13 * w + 10], 0)
    }

    // MARK: Composición

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let i = y * image.width * 4 + x * 4
        return [p[i], p[i + 1], p[i + 2]]
    }

    private func assertColor(_ got: [UInt8], _ expected: [UInt8], _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        let close = zip(got, expected).allSatisfy { abs(Int($0) - Int($1)) <= 3 }
        XCTAssertTrue(close, "\(got) ≠ \(expected) \(message)", file: file, line: line)
    }

    func testCompositeOnlyChangesMaskedPixelsAndKeepsOrientation() {
        let original = solid(255, 0, 0, width: 40, height: 20)
        // FLUX devuelve otro tamaño: se escala al del original.
        let generated = solid(0, 0, 255, width: 80, height: 40)
        var alpha = [UInt8](repeating: 0, count: 40 * 20)
        // Mitad superior izquierda.
        for y in 0..<10 { for x in 0..<20 { alpha[y * 40 + x] = 255 } }
        alpha[15 * 40 + 30] = 128

        let out = MaskFill.composite(original: original, generated: generated, alpha: alpha)!
        XCTAssertEqual(out.width, 40)
        XCTAssertEqual(out.height, 20)
        assertColor(pixel(out, x: 5, y: 5), [0, 0, 255], "arriba a la izquierda: resultado de FLUX")
        assertColor(pixel(out, x: 35, y: 5), [255, 0, 0], "fuera de la máscara: original intacto")
        assertColor(pixel(out, x: 5, y: 15), [255, 0, 0], "abajo: original intacto")
        let mid = pixel(out, x: 30, y: 15)
        XCTAssertTrue((120...135).contains(Int(mid[0])) && (120...135).contains(Int(mid[2])), "mezcla al 50 %: \(mid)")
    }

    func testCompositeFileEndToEnd() throws {
        func png(_ image: CGImage) -> Data {
            let out = NSMutableData()
            let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            return out as Data
        }
        let original = png(solid(0, 255, 0, width: 100, height: 100))
        let generated = png(solid(0, 0, 255, width: 64, height: 64))
        let square = MaskStroke(points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.1),
                                         CGPoint(x: 0.4, y: 0.4), CGPoint(x: 0.1, y: 0.4)],
                                radius: 0, erases: false, isPolygon: true)
        let result = try MaskFill.compositeFile(originalData: original, generatedData: generated,
                                                strokes: [square], inverted: false,
                                                grow: 0, feather: 0, format: .png)
        XCTAssertEqual(result.mimeType, "image/png")
        let source = CGImageSourceCreateWithData(result.data as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        XCTAssertEqual(image.width, 100, "se mantiene el tamaño de la foto original")
        assertColor(pixel(image, x: 25, y: 25), [0, 0, 255])
        assertColor(pixel(image, x: 75, y: 75), [0, 255, 0])
        assertColor(pixel(image, x: 25, y: 75), [0, 255, 0])
    }

    func testCompositeFileRejectsUnreadableData() {
        XCTAssertThrowsError(try MaskFill.compositeFile(originalData: Data([1, 2, 3]), generatedData: Data(),
                                                        strokes: [], inverted: false)) { error in
            XCTAssertEqual(error as? MaskFill.FillError, .unreadableOriginal)
        }
    }
}
