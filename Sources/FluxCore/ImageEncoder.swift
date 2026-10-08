import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepara imágenes de entrada para la API: corrige la orientación, reduce si
/// son demasiado grandes y las codifica en base64 (JPEG, o PNG si tienen transparencia).
public enum ImageEncoder {
    /// Lado largo máximo que se envía (~4 MP en 16:9). Más grande solo encarece y ralentiza.
    public static let defaultMaxDimension = 2560

    public struct Encoded: Sendable, Equatable {
        public let base64: String
        public let pixelWidth: Int
        public let pixelHeight: Int
        public let isPNG: Bool

        public var aspectRatio: Double { Double(pixelWidth) / Double(max(pixelHeight, 1)) }
        public var megapixels: Double { Double(pixelWidth * pixelHeight) / 1_000_000 }
    }

    public enum EncodeError: LocalizedError, Equatable {
        case unreadable
        case encodeFailed

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "No se puede leer la imagen (¿formato no compatible?)."
            case .encodeFailed: return "No se ha podido preparar la imagen para enviarla."
            }
        }
    }

    public static func encode(fileURL: URL, maxDimension: Int = defaultMaxDimension) throws -> Encoded {
        guard let data = try? Data(contentsOf: fileURL) else { throw EncodeError.unreadable }
        return try encode(data: data, maxDimension: maxDimension)
    }

    public static func encode(data: Data, maxDimension: Int = defaultMaxDimension, jpegQuality: Double = 0.9) throws -> Encoded {
        let image = try normalizedImage(data: data, maxDimension: maxDimension)
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast: hasAlpha = true
        default: hasAlpha = false
        }
        let type: UTType = hasAlpha ? .png : .jpeg
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw EncodeError.encodeFailed
        }
        let props: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw EncodeError.encodeFailed }
        return Encoded(
            base64: (output as Data).base64EncodedString(),
            pixelWidth: image.width,
            pixelHeight: image.height,
            isPNG: hasAlpha
        )
    }

    /// Imagen con la orientación EXIF aplicada y el lado largo ≤ maxDimension (nunca amplía).
    public static func normalizedImage(data: Data, maxDimension: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw EncodeError.unreadable
        }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let longSide = max(w, h)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide > 0 ? min(longSide, maxDimension) : maxDimension,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw EncodeError.unreadable
        }
        return image
    }

    /// Tamaño en píxeles sin decodificar la imagen entera.
    public static func pixelSize(fileURL: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    /// Miniatura rápida para mostrar en la interfaz.
    public static func thumbnail(fileURL: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
