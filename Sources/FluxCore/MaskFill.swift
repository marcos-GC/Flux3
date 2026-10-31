import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// «Pintar y rellenar»: inpainting con máscara sobre FLUX 3 Image.
///
/// FLUX 3 Image no acepta máscara, así que se hace en dos pasos, como en ComfyUI:
/// 1. Se envía la imagen entera con un prompt de edición que señala la caja de la zona pintada
///    (el mismo formato que «Editar»).
/// 2. Del resultado solo se copia lo que hay dentro de la zona pintada (con el borde suavizado)
///    sobre la foto original. Lo de fuera queda idéntico, píxel a píxel.
public enum MaskFill {
    /// Píxeles que se agranda la zona pintada antes de pegar (por defecto).
    public static let defaultGrow = 6
    /// Anchura del borde suavizado, en píxeles (por defecto).
    public static let defaultFeather = 12
    /// Lado largo máximo de la foto original al componer (más grande es lento y no aporta).
    public static let maxCompositeDimension = 8192

    // MARK: - Máscara

    /// Caja que encierra los píxeles blancos de una máscara (`width * height` bytes), o nil si está vacía.
    public static func boundingBox(mask: [UInt8], width: Int, height: Int) -> PixelRect? {
        guard width > 0, height > 0, mask.count >= width * height else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where mask[row + x] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return PixelRect(x: Double(minX), y: Double(minY), width: Double(maxX - minX + 1), height: Double(maxY - minY + 1))
    }

    /// Caja de la zona pintada, en píxeles de una imagen de `imageWidth × imageHeight`.
    /// Se calcula sobre una máscara reducida (rápido) y se agranda un poco para dar contexto al modelo.
    public static func paintedBox(strokes: [MaskStroke], inverted: Bool, imageWidth: Double, imageHeight: Double,
                                  margin: Double = 0.02) -> PixelRect? {
        guard imageWidth > 0, imageHeight > 0 else { return nil }
        let scale = min(1, 512 / max(imageWidth, imageHeight))
        let w = max(1, Int((imageWidth * scale).rounded()))
        let h = max(1, Int((imageHeight * scale).rounded()))
        let bitmap = MaskRenderer.renderBitmap(strokes: strokes, inverted: inverted, width: w, height: h)
        guard let box = boundingBox(mask: bitmap, width: w, height: h) else { return nil }
        let sx = imageWidth / Double(w), sy = imageHeight / Double(h)
        let pad = margin * max(imageWidth, imageHeight)
        let x0 = max(0, box.x * sx - pad), y0 = max(0, box.y * sy - pad)
        let x1 = min(imageWidth, box.maxX * sx + pad), y1 = min(imageHeight, box.maxY * sy + pad)
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Opacidad con la que se pega el resultado (0–255 por píxel): la zona pintada agrandada
    /// `grow` píxeles queda totalmente cubierta y el borde se funde en unos `feather` píxeles hacia fuera.
    public static func featheredAlpha(mask: [UInt8], width: Int, height: Int, grow: Int, feather: Int) -> [UInt8] {
        guard width > 0, height > 0, mask.count >= width * height else { return [] }
        let grow = max(0, grow), feather = max(0, feather)
        var alpha = dilate(mask, width: width, height: height, radius: grow + feather)
        if feather > 0 {
            // Dos pasadas de caja ≈ difuminado gaussiano. El radio total es `feather`.
            let r1 = (feather + 1) / 2, r2 = feather / 2
            alpha = boxBlur(alpha, width: width, height: height, radius: r1)
            if r2 > 0 { alpha = boxBlur(alpha, width: width, height: height, radius: r2) }
        }
        return alpha
    }

    /// Dilatación cuadrada: un píxel queda blanco si hay alguno blanco a ≤ `radius` en x e y.
    static func dilate(_ src: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        let binary = src.map { $0 >= 128 ? UInt8(255) : 0 }
        guard radius > 0 else { return binary }
        let horizontal = slidingAny(binary, width: width, height: height, radius: radius, horizontal: true)
        return slidingAny(horizontal, width: width, height: height, radius: radius, horizontal: false)
    }

    private static func slidingAny(_ src: [UInt8], width: Int, height: Int, radius: Int, horizontal: Bool) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        let lines = horizontal ? height : width
        let length = horizontal ? width : height
        src.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { o in
                for line in 0..<lines {
                    func index(_ i: Int) -> Int { horizontal ? line * width + i : i * width + line }
                    var count = 0
                    for i in 0..<min(radius, length) where s[index(i)] != 0 { count += 1 }
                    for i in 0..<length {
                        let add = i + radius, remove = i - radius - 1
                        if add < length, s[index(add)] != 0 { count += 1 }
                        if remove >= 0, s[index(remove)] != 0 { count -= 1 }
                        o[index(i)] = count > 0 ? 255 : 0
                    }
                }
            }
        }
        return out
    }

    /// Media en una caja de lado `2·radius + 1` (separable). Fuera de la imagen cuenta como el borde.
    static func boxBlur(_ src: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        guard radius > 0 else { return src }
        let horizontal = blurPass(src, width: width, height: height, radius: radius, horizontal: true)
        return blurPass(horizontal, width: width, height: height, radius: radius, horizontal: false)
    }

    private static func blurPass(_ src: [UInt8], width: Int, height: Int, radius: Int, horizontal: Bool) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height)
        let lines = horizontal ? height : width
        let length = horizontal ? width : height
        let window = 2 * radius + 1
        src.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { o in
                for line in 0..<lines {
                    func value(_ i: Int) -> Int {
                        let c = min(max(i, 0), length - 1)
                        return Int(s[horizontal ? line * width + c : c * width + line])
                    }
                    var sum = 0
                    for i in -radius...radius { sum += value(i) }
                    for i in 0..<length {
                        o[horizontal ? line * width + i : i * width + line] = UInt8((sum + window / 2) / window)
                        sum += value(i + radius + 1) - value(i - radius)
                    }
                }
            }
        }
        return out
    }

    // MARK: - Prompt

    /// Prompt para FLUX 3 Image (la foto va en `images[0]`; la referencia opcional, en `images[1]`).
    /// Usa el mismo formato que «Editar» con una sola región.
    public static func prompt(instruction: String, box: PixelRect, imageWidth: Double, imageHeight: Double,
                              hasReference: Bool = false) -> String {
        let region = EditRegionSpec(number: 1, kind: .edit, source: box, instruction: instruction,
                                    referenceImageIndex: hasReference ? 1 : nil)
        return PreciseEdit.buildPrompt(globalInstruction: "", regions: [region],
                                       imageWidth: imageWidth, imageHeight: imageHeight)
    }

    // MARK: - Composición

    public enum FillError: LocalizedError, Equatable {
        case unreadableOriginal
        case unreadableResult
        case compositeFailed

        public var errorDescription: String? {
            switch self {
            case .unreadableOriginal: return "No se ha podido leer la foto original para pegar el resultado."
            case .unreadableResult: return "No se ha podido leer la imagen que ha devuelto FLUX."
            case .compositeFailed: return "No se ha podido pegar el resultado sobre la foto original."
            }
        }
    }

    /// Pega `generated` sobre `original` solo donde `alpha` (máscara al tamaño del original) es > 0.
    /// El resultado se escala al tamaño del original. Devuelve una imagen RGBA del tamaño del original.
    public static func composite(original: CGImage, generated: CGImage, alpha: [UInt8]) -> CGImage? {
        let width = original.width, height = original.height
        guard width > 0, height > 0, alpha.count == width * height,
              let base = rgbaContext(width: width, height: height),
              let top = rgbaContext(width: width, height: height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        base.draw(original, in: rect)
        top.interpolationQuality = .high
        top.draw(generated, in: rect)
        guard let baseData = base.data, let topData = top.data else { return nil }
        let rowBytes = base.bytesPerRow, topRowBytes = top.bytesPerRow
        let b = baseData.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        let t = topData.bindMemory(to: UInt8.self, capacity: topRowBytes * height)
        alpha.withUnsafeBufferPointer { a in
            // Las filas del contexto van de arriba abajo, igual que la máscara.
            for y in 0..<height {
                for x in 0..<width {
                    let k = Int(a[y * width + x])
                    guard k > 0 else { continue }
                    let bi = y * rowBytes + x * 4, ti = y * topRowBytes + x * 4
                    if k == 255 {
                        b[bi] = t[ti]; b[bi + 1] = t[ti + 1]; b[bi + 2] = t[ti + 2]; b[bi + 3] = t[ti + 3]
                    } else {
                        for c in 0..<4 {
                            b[bi + c] = UInt8((Int(t[ti + c]) * k + Int(b[bi + c]) * (255 - k) + 127) / 255)
                        }
                    }
                }
            }
        }
        return base.makeImage()
    }

    private static func rgbaContext(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Paso completo: lee la foto original y el resultado de FLUX, pinta la máscara al tamaño
    /// del original y devuelve la imagen compuesta codificada (datos y tipo MIME).
    public static func compositeFile(
        originalData: Data, generatedData: Data, strokes: [MaskStroke], inverted: Bool,
        grow: Int = defaultGrow, feather: Int = defaultFeather, format: ToolOutputFormat = .jpeg
    ) throws -> (data: Data, mimeType: String) {
        guard let original = try? ImageEncoder.normalizedImage(data: originalData, maxDimension: maxCompositeDimension)
        else { throw FillError.unreadableOriginal }
        guard let source = CGImageSourceCreateWithData(generatedData as CFData, nil),
              let generated = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw FillError.unreadableResult }
        let mask = MaskRenderer.renderBitmap(strokes: strokes, inverted: inverted,
                                             width: original.width, height: original.height)
        // El grosor del borde se da para una foto de ~2000 px y se ajusta al tamaño real.
        let factor = max(Double(max(original.width, original.height)) / 2000, 0.25)
        let alpha = featheredAlpha(mask: mask, width: original.width, height: original.height,
                                   grow: Int((Double(grow) * factor).rounded()),
                                   feather: Int((Double(feather) * factor).rounded()))
        guard let image = composite(original: original, generated: generated, alpha: alpha),
              let encoded = encode(image, format: format) else { throw FillError.compositeFailed }
        return encoded
    }

    /// Codifica en el formato pedido. Si el sistema no sabe escribir WebP, se usa JPEG.
    public static func encode(_ image: CGImage, format: ToolOutputFormat) -> (data: Data, mimeType: String)? {
        let candidates: [(UTType, String)]
        switch format {
        case .png: candidates = [(.png, "image/png")]
        case .webp: candidates = [(.webP, "image/webp"), (.jpeg, "image/jpeg")]
        case .jpeg: candidates = [(.jpeg, "image/jpeg")]
        }
        for (type, mime) in candidates {
            let output = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { continue }
            let props: [CFString: Any] = type == .png ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.95]
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
            if CGImageDestinationFinalize(dest) { return (output as Data, mime) }
        }
        return nil
    }
}
