import CoreGraphics
import Foundation

/// Formato de salida de las FLUX Tools.
public enum ToolOutputFormat: String, CaseIterable, Sendable, Codable {
    case jpeg, png, webp
}

/// `POST /v1/flux-tools/outpainting-v1`
public struct OutpaintRequest: Encodable, Sendable, Equatable {
    public enum Mode: String, Sendable, Codable, CaseIterable { case high, fast }

    public var inputImage: String
    public var width: Int
    public var height: Int
    public var prompt: String?
    public var referenceOffsetX: Int?
    public var referenceOffsetY: Int?
    public var autoCrop: Bool?
    public var mode: Mode?
    public var disablePup: Bool?
    public var safetyTolerance: Int
    public var outputFormat: ToolOutputFormat

    enum CodingKeys: String, CodingKey {
        case inputImage = "input_image"
        case width, height, prompt, mode
        case referenceOffsetX = "reference_offset_x"
        case referenceOffsetY = "reference_offset_y"
        case autoCrop = "auto_crop"
        case disablePup = "disable_pup"
        case safetyTolerance = "safety_tolerance"
        case outputFormat = "output_format"
    }

    public init(inputImage: String, width: Int, height: Int, prompt: String = "", offset: CGPoint? = nil,
                autoCrop: Bool = false, mode: Mode = .high, disablePup: Bool = false,
                safetyTolerance: Int = SafetyTolerance.defaultValue, outputFormat: ToolOutputFormat = .jpeg) {
        self.inputImage = inputImage
        self.width = max(64, width)
        self.height = max(64, height)
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prompt = p.isEmpty ? nil : p
        self.referenceOffsetX = offset.map { Int($0.x.rounded()) }
        self.referenceOffsetY = offset.map { Int($0.y.rounded()) }
        self.autoCrop = autoCrop ? true : nil
        self.mode = mode
        self.disablePup = disablePup ? true : nil
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .outpaint)
        self.outputFormat = outputFormat
    }
}

/// `POST /v1/flux-tools/erase-v1`
public struct EraseRequest: Encodable, Sendable, Equatable {
    public var image: String
    public var mask: String
    public var dilatePixels: Int
    public var seed: Int?
    public var safetyTolerance: Int
    public var outputFormat: ToolOutputFormat

    enum CodingKeys: String, CodingKey {
        case image, mask, seed
        case dilatePixels = "dilate_pixels"
        case safetyTolerance = "safety_tolerance"
        case outputFormat = "output_format"
    }

    public init(image: String, mask: String, dilatePixels: Int = 10, seed: Int? = nil,
                safetyTolerance: Int = SafetyTolerance.defaultValue, outputFormat: ToolOutputFormat = .jpeg) {
        self.image = image
        self.mask = mask
        self.dilatePixels = min(25, max(0, dilatePixels))
        self.seed = seed
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .erase)
        self.outputFormat = outputFormat
    }
}

/// `POST /v1/flux-tools/deblur-v1`
public struct DeblurRequest: Encodable, Sendable, Equatable {
    public var image: String
    public var seed: Int?
    public var safetyTolerance: Int
    public var outputFormat: ToolOutputFormat

    enum CodingKeys: String, CodingKey {
        case image, seed
        case safetyTolerance = "safety_tolerance"
        case outputFormat = "output_format"
    }

    public init(image: String, seed: Int? = nil, safetyTolerance: Int = SafetyTolerance.defaultValue,
                outputFormat: ToolOutputFormat = .jpeg) {
        self.image = image
        self.seed = seed
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .deblur)
        self.outputFormat = outputFormat
    }
}

/// `POST /v1/flux-tools/vto-v2`
public struct TryOnRequest: Encodable, Sendable, Equatable {
    public var prompt: String
    public var person: String
    public var garment: String
    public var seed: Int?
    public var safetyTolerance: Int
    public var outputFormat: ToolOutputFormat

    enum CodingKeys: String, CodingKey {
        case prompt, person, garment, seed
        case safetyTolerance = "safety_tolerance"
        case outputFormat = "output_format"
    }

    public init(prompt: String, person: String, garment: String, seed: Int? = nil,
                safetyTolerance: Int = SafetyTolerance.defaultValue, outputFormat: ToolOutputFormat = .jpeg) {
        self.prompt = prompt
        self.person = person
        self.garment = garment
        self.seed = seed
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .vto)
        self.outputFormat = outputFormat
    }

    /// Fórmula recomendada por BFL para el probador.
    public static func prompt(forGarment garment: String) -> String {
        let g = garment.trimmingCharacters(in: .whitespacesAndNewlines)
        return "The person of image 1, maintaining exactly their face and pose, wearing the \(g.isEmpty ? "garment" : g) of image 2."
    }
}

/// Cálculos del lienzo de Outpainting (en píxeles de la imagen que se envía).
public enum OutpaintGeometry {
    /// Múltiplo al que se redondean ancho y alto del lienzo.
    public static let step = 16.0

    /// Lienzo mínimo con la proporción pedida que contiene la imagen, ampliado por `expand` (≥ 1).
    public static func canvas(for source: CGSize, ratio: Double?, expand: Double) -> CGSize {
        let w = max(1, source.width), h = max(1, source.height)
        var cw = w, ch = h
        if let ratio, ratio > 0 {
            if w / h < ratio { cw = h * ratio } else { ch = w / ratio }
        }
        let e = max(1, expand)
        cw = max(roundUp(cw * e), roundUp(w), 64)
        ch = max(roundUp(ch * e), roundUp(h), 64)
        return CGSize(width: cw, height: ch)
    }

    /// Posición de la esquina superior izquierda de la imagen para que quede centrada.
    public static func centeredOffset(source: CGSize, canvas: CGSize) -> CGPoint {
        CGPoint(x: ((canvas.width - source.width) / 2).rounded(), y: ((canvas.height - source.height) / 2).rounded())
    }

    /// Mantiene la imagen dentro del lienzo.
    public static func clamp(_ offset: CGPoint, source: CGSize, canvas: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(0, offset.x), max(0, canvas.width - source.width)).rounded(),
            y: min(max(0, offset.y), max(0, canvas.height - source.height)).rounded()
        )
    }

    static func roundUp(_ v: Double) -> Double {
        (v / step).rounded(.up) * step
    }
}
