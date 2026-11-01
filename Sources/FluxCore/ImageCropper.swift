import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Recorte de imágenes con un rectángulo normalizado (0…1, origen arriba a la izquierda).
public enum ImageCropper {
    public enum CropError: Error, LocalizedError {
        case unreadable, tooSmall, encodeFailed

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "No se puede leer la imagen."
            case .tooSmall: return "El recorte es demasiado pequeño."
            case .encodeFailed: return "No se ha podido guardar el recorte."
            }
        }
    }

    /// Rectángulo en píxeles enteros dentro de la imagen (como mínimo 1×1).
    public static func pixelRect(normalized: CGRect, width: Int, height: Int) -> CGRect {
        let w = CGFloat(max(width, 1)), h = CGFloat(max(height, 1))
        let n = normalized.standardized
        let minX = min(max(0, (n.minX * w).rounded()), w - 1)
        let minY = min(max(0, (n.minY * h).rounded()), h - 1)
        let maxX = min(w, max(minX + 1, (n.maxX * w).rounded()))
        let maxY = min(h, max(minY + 1, (n.maxY * h).rounded()))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Recorta una imagen ya cargada.
    public static func crop(_ image: CGImage, normalized: CGRect) throws -> CGImage {
        let rect = pixelRect(normalized: normalized, width: image.width, height: image.height)
        guard rect.width >= 8, rect.height >= 8 else { throw CropError.tooSmall }
        guard let cropped = image.cropping(to: rect) else { throw CropError.unreadable }
        return cropped
    }

    /// Carga la imagen a resolución completa, con la orientación EXIF aplicada (como se ve en pantalla).
    public static func loadOriented(fileURL: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Codifica el recorte: JPEG si el original lo era, PNG en los demás casos.
    public static func encode(_ image: CGImage, likeFile url: URL?) throws -> (data: Data, mimeType: String) {
        let ext = (url?.pathExtension ?? "").lowercased()
        let jpeg = ext == "jpg" || ext == "jpeg"
        let type = jpeg ? UTType.jpeg : UTType.png
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw CropError.encodeFailed
        }
        let options: [CFString: Any] = jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.95] : [:]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CropError.encodeFailed }
        return (data as Data, jpeg ? "image/jpeg" : "image/png")
    }
}
