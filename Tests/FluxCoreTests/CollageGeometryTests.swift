import CoreGraphics
import XCTest
@testable import FluxCore

final class CollageGeometryTests: XCTestCase {
    private let rect = CollageQuad(rect: CGRect(x: 100, y: 100, width: 200, height: 100))

    private func assertClose(_ a: CGPoint, _ b: CGPoint, accuracy: CGFloat = 1e-6,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: accuracy, file: file, line: line)
    }

    func testHomographyMapsUnitSquareToCorners() {
        let quad = CollageQuad(corners: [
            CGPoint(x: 10, y: 20), CGPoint(x: 300, y: 5), CGPoint(x: 280, y: 260), CGPoint(x: 40, y: 200),
        ])
        let h = quad.homography
        assertClose(h.apply(u: 0, v: 0), quad.corners[0])
        assertClose(h.apply(u: 1, v: 0), quad.corners[1])
        assertClose(h.apply(u: 1, v: 1), quad.corners[2])
        assertClose(h.apply(u: 0, v: 1), quad.corners[3])
    }

    func testHomographyOfRectangleIsAffine() {
        let h = rect.homography
        XCTAssertEqual(h.g, 0)
        XCTAssertEqual(h.h, 0)
        assertClose(h.apply(u: 0.5, v: 0.5), CGPoint(x: 200, y: 150))
    }

    func testMoveAndContains() {
        let moved = rect.translated(by: CGVector(dx: 50, dy: -20))
        assertClose(moved.topLeft, CGPoint(x: 150, y: 80))
        XCTAssertTrue(moved.contains(CGPoint(x: 200, y: 120)))
        XCTAssertFalse(moved.contains(CGPoint(x: 120, y: 120)))
    }

    func testCornerScaleKeepsOppositeCornerAndProportion() {
        // Arrastrar la esquina abajo-derecha hasta el doble: arriba-izquierda no se mueve.
        let scaled = rect.scaledFromCorner(2, to: CGPoint(x: 500, y: 300))
        assertClose(scaled.topLeft, CGPoint(x: 100, y: 100))
        assertClose(scaled.bottomRight, CGPoint(x: 500, y: 300))
        XCTAssertEqual(scaled.approximateSize.width / scaled.approximateSize.height, 2, accuracy: 1e-6)
    }

    func testEdgeStretchChangesOnlyOneDimension() {
        // Lado derecho (1) 40 px hacia fuera: más ancho, misma altura.
        let wider = rect.stretchedEdge(1, by: CGVector(dx: 40, dy: 15))
        XCTAssertEqual(wider.approximateSize.width, 240, accuracy: 1e-6)
        XCTAssertEqual(wider.approximateSize.height, 100, accuracy: 1e-6)
        assertClose(wider.topLeft, rect.topLeft)
        // No se puede invertir: se queda con un tamaño mínimo.
        let collapsed = rect.stretchedEdge(2, by: CGVector(dx: 0, dy: -500))
        XCTAssertGreaterThan(collapsed.approximateSize.height, 1)
    }

    func testRotateQuarterTurnAroundCenter() {
        let turned = rect.rotated(by: .pi / 2)
        assertClose(turned.center, rect.center)
        XCTAssertEqual(turned.approximateSize.width, 200, accuracy: 1e-6)
        assertClose(turned.topLeft, CGPoint(x: 250, y: 50))
    }

    func testCornerDistortRejectsCrossedShapes() {
        let ok = rect.movingCorner(1, to: CGPoint(x: 320, y: 80))
        assertClose(ok.topRight, CGPoint(x: 320, y: 80))
        XCTAssertTrue(ok.isConvex)
        // Llevar una esquina al otro lado cruzaría la forma: se ignora.
        let crossed = rect.movingCorner(1, to: CGPoint(x: 50, y: 250))
        XCTAssertEqual(crossed, rect)
    }

    func testFlipSwapsSides() {
        let flipped = rect.flippedHorizontally
        assertClose(flipped.topLeft, rect.topRight)
        assertClose(flipped.bottomRight, rect.bottomLeft)
        XCTAssertEqual(flipped.flippedHorizontally, rect)
    }

    func testCollagePromptMentionsReferences() {
        let none = CollagePrompt.build(extra: "", referenceCount: 0)
        XCTAssertTrue(none.contains("image 1"))
        XCTAssertFalse(none.contains("image 2"))
        let some = CollagePrompt.build(extra: "warm evening light", referenceCount: 2)
        XCTAssertTrue(some.contains("image 2, image 3"))
        XCTAssertTrue(some.hasSuffix("warm evening light."))
    }

    func testInverseHomographyRoundTrip() throws {
        let quad = CollageQuad(corners: [
            CGPoint(x: 10, y: 20), CGPoint(x: 300, y: 5), CGPoint(x: 280, y: 260), CGPoint(x: 40, y: 200),
        ])
        let h = quad.homography
        let samples: [(CGFloat, CGFloat)] = [(0, 0), (0.3, 0.7), (1, 1), (0.5, 0.25)]
        for (u, v) in samples {
            let p = h.apply(u: u, v: v)
            let back = try XCTUnwrap(h.invert(p))
            XCTAssertEqual(back.x, u, accuracy: 1e-6)
            XCTAssertEqual(back.y, v, accuracy: 1e-6)
        }
        // Fuera de la capa da valores fuera de 0…1.
        let outside = try XCTUnwrap(h.invert(CGPoint(x: -100, y: -100)))
        XCTAssertTrue(outside.x < 0 || outside.y < 0)
    }

    func testProjectFileRoundTrip() throws {
        let layer = CollageProjectFile.Layer(
            id: UUID(), source: "/tmp/cuenco.png", imageFile: "capa.png", maskFile: nil,
            corners: rect.cornerArrays, opacity: 0.8, visible: true, cutOut: true
        )
        let file = CollageProjectFile(
            name: "Librería salón", created: Date(timeIntervalSince1970: 1_790_000_000),
            modified: Date(timeIntervalSince1970: 1_790_000_600), baseFile: "base.png", baseSource: nil,
            extraPrompt: "luz de tarde", resolution: "2k", sendOriginals: true, layers: [layer]
        )
        let decoded = try CollageProjectFile.decode(try file.encoded())
        XCTAssertEqual(decoded, file)
        XCTAssertEqual(decoded.layers.first?.quad, rect)
    }
}
