import Foundation

/// Opciones de FLUX 3 Image según la documentación.
public enum Flux3Image {
    public static let aspectRatios = [
        "auto", "21:9", "2:1", "16:9", "3:2", "7:5", "4:3", "5:4", "1:1",
        "4:5", "3:4", "5:7", "2:3", "9:16", "1:2", "9:21",
    ]
    public static let resolutions = ["768sq", "1k", "1.5k", "2k", "4k"]
    public static let maxReferenceImages = 10

    public static func resolutionLabel(_ value: String) -> String {
        switch value {
        case "768sq": return "768 · 0,6 MP"
        case "1k": return "1K · 1 MP"
        case "1.5k": return "1,5K · 2,4 MP"
        case "2k": return "2K · 4 MP"
        case "4k": return "4K · 16 MP"
        default: return value
        }
    }
}

/// Cuerpo de `POST /v1/flux-3-image`. Solo se envían los campos con valor distinto
/// del de por defecto: la API rechaza (422) campos que no conoce.
public struct Flux3ImageRequest: Encodable, Sendable, Equatable {
    public var prompt: String
    public var images: [String]?
    public var aspectRatio: String?
    public var resolution: String?
    public var safetyTolerance: Int?
    public var grounding: Bool?

    enum CodingKeys: String, CodingKey {
        case prompt, images, resolution, grounding
        case aspectRatio = "aspect_ratio"
        case safetyTolerance = "safety_tolerance"
    }

    public init(
        prompt: String,
        images: [String] = [],
        aspectRatio: String = "auto",
        resolution: String = "1k",
        safetyTolerance: Int = SafetyTolerance.defaultValue,
        grounding: Bool = true
    ) {
        self.prompt = prompt
        self.images = images.isEmpty ? nil : Array(images.prefix(Flux3Image.maxReferenceImages))
        self.aspectRatio = aspectRatio == "auto" ? nil : aspectRatio
        self.resolution = resolution
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .flux3Image)
        self.grounding = grounding ? nil : false
    }
}

/// Ajustes de FLUX 3 Image recuperados de los parámetros guardados en un .json
/// (para "Reutilizar parámetros"). Los campos que no se enviaron toman su valor por defecto.
public struct Flux3ImageSettings: Equatable, Sendable {
    public var aspectRatio = "auto"
    public var resolution = "1k"
    public var safetyTolerance = SafetyTolerance.defaultValue
    public var grounding = true

    public init() {}

    public init(parameters: JSONValue) {
        aspectRatio = parameters["aspect_ratio"]?.stringValue ?? "auto"
        resolution = parameters["resolution"]?.stringValue ?? "1k"
        if let n = parameters["safety_tolerance"]?.numberValue {
            safetyTolerance = SafetyTolerance.clamp(Int(n), for: .flux3Image)
        }
        if case .bool(let b)? = parameters["grounding"] {
            grounding = b
        }
    }
}
