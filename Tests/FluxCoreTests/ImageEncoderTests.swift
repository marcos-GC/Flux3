import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FluxCore

final class ImageEncoderTests: XCTestCase {
    /// Crea una imagen PNG de prueba en memoria.
    private func makePNG(width: Int, height: Int, alpha: Bool) throws -> Data {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info
        ))
        ctx.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.9, alpha: alpha ? 0.5 : 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return data as Data
    }

    func testLargeImageIsDownscaledKeepingAspect() throws {
        let png = try makePNG(width: 4000, height: 1000, alpha: false)
        let encoded = try ImageEncoder.encode(data: png, maxDimension: 2048)
        XCTAssertEqual(encoded.pixelWidth, 2048)
        XCTAssertEqual(encoded.pixelHeight, 512)
        XCTAssertEqual(encoded.aspectRatio, 4, accuracy: 0.01)
    }

    func testSmallImageIsNotUpscaled() throws {
        let png = try makePNG(width: 300, height: 200, alpha: false)
        let encoded = try ImageEncoder.encode(data: png, maxDimension: 2048)
        XCTAssertEqual(encoded.pixelWidth, 300)
        XCTAssertEqual(encoded.pixelHeight, 200)
    }

    func testOpaqueBecomesJPEGAndTransparentStaysPNG() throws {
        let opaque = try ImageEncoder.encode(data: try makePNG(width: 64, height: 64, alpha: false))
        let opaqueBytes = try XCTUnwrap(Data(base64Encoded: opaque.base64))
        XCTAssertFalse(opaque.isPNG)
        XCTAssertEqual(Array(opaqueBytes.prefix(2)), [0xFF, 0xD8]) // cabecera JPEG

        let transparent = try ImageEncoder.encode(data: try makePNG(width: 64, height: 64, alpha: true))
        let pngBytes = try XCTUnwrap(Data(base64Encoded: transparent.base64))
        XCTAssertTrue(transparent.isPNG)
        XCTAssertEqual(Array(pngBytes.prefix(4)), [0x89, 0x50, 0x4E, 0x47]) // cabecera PNG
    }

    func testUnreadableData() {
        XCTAssertThrowsError(try ImageEncoder.encode(data: Data("no es una imagen".utf8))) { error in
            XCTAssertEqual(error as? ImageEncoder.EncodeError, .unreadable)
        }
    }
}
