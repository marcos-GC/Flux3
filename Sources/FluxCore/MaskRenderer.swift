import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Trazo de pincel para la máscara de Borrar. Coordenadas normalizadas (0–1) sobre la imagen.
public struct MaskStroke: Equatable, Sendable {
    public var points: [CGPoint]
    /// Radio del pincel como fracción del ancho de la imagen.
    public var radius: Double
    /// true = goma (quita máscara).
    public var erases: Bool

    public init(points: [CGPoint], radius: Double, erases: Bool) {
        self.points = points
        self.radius = radius
        self.erases = erases
    }
}

/// Convierte los trazos en la máscara en blanco y negro que espera la API
/// (mismo tamaño que la imagen; blanco = borrar).
public enum MaskRenderer {
    /// Si la máscara no tiene nada que borrar.
    public static func isEmpty(strokes: [MaskStroke], inverted: Bool) -> Bool {
        !inverted && !strokes.contains { !$0.erases && !$0.points.isEmpty }
    }

    /// Píxeles en escala de grises (0 o 255), fila a fila desde arriba. `width * height` bytes.
    public static func renderBitmap(strokes: [MaskStroke], inverted: Bool, width: Int, height: Int) -> [UInt8] {
        guard let context = makeContext(strokes: strokes, inverted: inverted, width: width, height: height),
              let data = context.data else { return [] }
        let bytesPerRow = context.bytesPerRow
        let raw = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var out = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                out[y * width + x] = raw[y * bytesPerRow + x] >= 128 ? 255 : 0
            }
        }
        return out
    }

    /// PNG en escala de grises listo para enviar (en base64 con `.base64EncodedString()`).
    public static func pngData(strokes: [MaskStroke], inverted: Bool, width: Int, height: Int) -> Data? {
        guard let context = makeContext(strokes: strokes, inverted: inverted, width: width, height: height),
              let image = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? output as Data : nil
    }

    private static func makeContext(strokes: [MaskStroke], inverted: Bool, width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        // Coordenadas con el origen arriba a la izquierda, como en pantalla.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(false)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let background: CGFloat = inverted ? 1 : 0
        ctx.setFillColor(gray: background, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        for stroke in strokes where !stroke.points.isEmpty {
            // Pincel = blanco (borrar); goma = negro. Invertir intercambia los dos.
            let paintsWhite = stroke.erases == inverted
            let value: CGFloat = paintsWhite ? 1 : 0
            ctx.setStrokeColor(gray: value, alpha: 1)
            ctx.setFillColor(gray: value, alpha: 1)
            let r = CGFloat(stroke.radius) * CGFloat(width)
            let pts = stroke.points.map { CGPoint(x: $0.x * CGFloat(width), y: $0.y * CGFloat(height)) }
            if pts.count == 1 {
                ctx.fillEllipse(in: CGRect(x: pts[0].x - r, y: pts[0].y - r, width: r * 2, height: r * 2))
            } else {
                ctx.setLineWidth(r * 2)
                ctx.addLines(between: pts)
                ctx.strokePath()
            }
        }
        return ctx
    }
}
