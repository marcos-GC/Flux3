import CoreGraphics
import XCTest
@testable import FluxCore

final class ImageCropperTests: XCTestCase {
    func testPixelRectRoundsAndClamps() {
        let r = ImageCropper.pixelRect(normalized: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5), width: 1000, height: 800)
        XCTAssertEqual(r, CGRect(x: 250, y: 400, width: 500, height: 400))

        let outside = ImageCropper.pixelRect(normalized: CGRect(x: -0.2, y: -0.1, width: 2, height: 2), width: 100, height: 50)
        XCTAssertEqual(outside, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func testCropKeepsTopLeftOrigin() throws {
        // Mitad de arriba roja, mitad de abajo azul.
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 40, height: 20)) // abajo (CG cuenta la y desde abajo)
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 20, width: 40, height: 20)) // arriba
        let image = try XCTUnwrap(ctx.makeImage())

        let top = try ImageCropper.crop(image, normalized: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(top.width, 40)
        XCTAssertEqual(top.height, 20)
        let pixel = try XCTUnwrap(firstPixel(top))
        XCTAssertGreaterThan(pixel.r, 200)
        XCTAssertLessThan(pixel.b, 50)
    }

    func testTinyCropIsRejected() throws {
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try XCTUnwrap(ctx.makeImage())
        XCTAssertThrowsError(try ImageCropper.crop(image, normalized: CGRect(x: 0.5, y: 0.5, width: 0.02, height: 0.5)))
    }

    private func firstPixel(_ image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8)? {
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // Se pinta el píxel de arriba a la izquierda en el contexto de 1×1.
        ctx.draw(image, in: CGRect(x: 0, y: -CGFloat(image.height - 1), width: CGFloat(image.width), height: CGFloat(image.height)))
        return (data[0], data[1], data[2])
    }
}
