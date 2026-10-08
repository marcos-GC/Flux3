import Foundation

/// Opciones de FLUX 3 Video según la documentación.
public enum Flux3Video {
    public static let aspectRatios = ["auto", "21:9", "2:1", "16:9", "4:3", "1:1", "3:4", "9:16", "9:21"]
    /// La documentación solo admite hd y fhd (para más, usar el escalado de vídeo).
    public static let resolutions = ["hd", "fhd"]
    public static let durations = 5...20
    public static let maxKeyframes = 10
    public static let minKeyframeSide = 256
    /// Límites de los vídeos de entrada.
    public static let maxContinueSeconds = 15.0
    public static let maxEditSeconds = 15.0
    public static let maxUpscaleSeconds = 20.0
    public static let maxUpscaleSize = (width: 2560, height: 1440)
    public static let maxVideoBytes = 50 * 1024 * 1024

    public static func resolutionLabel(_ value: String) -> String {
        value == "fhd" ? "Full HD" : "HD"
    }
}

/// `POST /v1/flux-3-video`. Solo se envían los campos con valor distinto del de por defecto:
/// la API rechaza (422) los campos que no conoce.
public struct Flux3VideoRequest: Encodable, Sendable, Equatable {
    public enum Mode: String, Sendable, Codable, CaseIterable {
        case t2v, i2v, v2v
        case draftEnhance = "draft_enhance"
    }

    public struct Keyframe: Sendable, Equatable {
        public var image: String
        /// Segundo en el que debe aparecer (todos con tiempo o ninguno).
        public var seconds: Double?

        public init(image: String, seconds: Double? = nil) {
            self.image = image
            self.seconds = seconds
        }
    }

    public var mode: Mode
    public var prompt: String?
    public var keyframes: [Keyframe]?
    public var startVideo: String?
    public var draftCache: String?
    public var aspectRatio: String?
    /// nil = "auto".
    public var duration: Int?
    public var resolution: String?
    public var generateAudio: Bool
    public var draft: Bool
    public var safetyTolerance: Int?

    public init(mode: Mode, prompt: String, keyframes: [Keyframe]? = nil, startVideo: String? = nil,
                aspectRatio: String = "auto", duration: Int? = nil, resolution: String = "hd",
                generateAudio: Bool = true, draft: Bool = false,
                safetyTolerance: Int = SafetyTolerance.defaultValue) {
        self.mode = mode
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prompt = p.isEmpty ? nil : p
        self.keyframes = keyframes
        self.startVideo = startVideo
        self.aspectRatio = aspectRatio == "auto" ? nil : aspectRatio
        self.duration = duration.map { min(max($0, Flux3Video.durations.lowerBound), Flux3Video.durations.upperBound) }
        // Los borradores se generan siempre en HD.
        self.resolution = draft ? "hd" : resolution
        self.generateAudio = generateAudio
        self.draft = draft
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .flux3Video)
    }

    /// Render a calidad final de un borrador: solo `mode` y `draft_cache`
    /// (y la resolución únicamente si se pide HD en lugar de Full HD).
    public static func draftEnhance(cache: String, resolution: String? = nil) -> Flux3VideoRequest {
        var r = Flux3VideoRequest(mode: .draftEnhance, prompt: "")
        r.draftCache = cache
        r.resolution = resolution == "hd" ? "hd" : nil
        r.aspectRatio = nil
        r.safetyTolerance = nil
        return r
    }

    enum CodingKeys: String, CodingKey {
        case mode, prompt, keyframes, duration, resolution, draft
        case startVideo = "start_video"
        case draftCache = "draft_cache"
        case aspectRatio = "aspect_ratio"
        case generateAudio = "generate_audio"
        case safetyTolerance = "safety_tolerance"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode.rawValue, forKey: .mode)
        if mode == .draftEnhance {
            try c.encodeIfPresent(draftCache, forKey: .draftCache)
            try c.encodeIfPresent(resolution, forKey: .resolution)
            return
        }
        try c.encodeIfPresent(prompt, forKey: .prompt)
        if mode == .i2v, let keyframes {
            var list = c.nestedUnkeyedContainer(forKey: .keyframes)
            let timed = keyframes.allSatisfy { $0.seconds != nil }
            for frame in keyframes {
                if timed, let seconds = frame.seconds {
                    var pair = list.nestedUnkeyedContainer()
                    if seconds.rounded() == seconds { try pair.encode(Int(seconds)) } else { try pair.encode(seconds) }
                    try pair.encode(frame.image)
                } else {
                    try list.encode(frame.image)
                }
            }
        }
        if mode == .v2v { try c.encodeIfPresent(startVideo, forKey: .startVideo) }
        try c.encodeIfPresent(aspectRatio, forKey: .aspectRatio)
        try c.encodeIfPresent(duration, forKey: .duration)
        try c.encodeIfPresent(resolution, forKey: .resolution)
        if !generateAudio { try c.encode(false, forKey: .generateAudio) }
        if draft { try c.encode(true, forKey: .draft) }
        try c.encodeIfPresent(safetyTolerance, forKey: .safetyTolerance)
    }

    /// Comprueba las reglas de la documentación. Devuelve el problema en español, o nil.
    public func validationError() -> String? {
        switch mode {
        case .t2v:
            if prompt == nil { return "Escribe qué debe pasar en el vídeo." }
        case .i2v:
            let frames = keyframes ?? []
            if frames.isEmpty { return "Añade al menos un fotograma clave." }
            if frames.count > Flux3Video.maxKeyframes { return "Como máximo \(Flux3Video.maxKeyframes) fotogramas clave." }
            let timed = frames.filter { $0.seconds != nil }.count
            if timed != 0 && timed != frames.count { return "Pon segundo a todos los fotogramas o a ninguno." }
            if timed == frames.count {
                let secs = frames.compactMap(\.seconds)
                if zip(secs, secs.dropFirst()).contains(where: { $0 >= $1 }) {
                    return "Los segundos de los fotogramas deben ir en orden creciente."
                }
                if let d = duration, let last = secs.last, last > Double(d) {
                    return "El último fotograma (\(Int(last)) s) cae fuera de la duración (\(d) s)."
                }
            } else if frames.count >= 3 && duration == nil {
                return "Con 3 o más fotogramas sin segundos fijados, elige una duración concreta (no «Auto»)."
            }
        case .v2v:
            if startVideo == nil { return "Selecciona el vídeo que quieres continuar." }
        case .draftEnhance:
            if draftCache == nil { return "Este vídeo no tiene borrador para renderizar." }
        }
        return nil
    }
}

/// `POST /v1/flux-tools/video-edit-v1`
public struct VideoEditRequest: Encodable, Sendable, Equatable {
    public var video: String
    public var prompt: String
    public var safetyTolerance: Int

    enum CodingKeys: String, CodingKey {
        case video, prompt
        case safetyTolerance = "safety_tolerance"
    }

    public init(video: String, prompt: String, safetyTolerance: Int = SafetyTolerance.defaultValue) {
        self.video = video
        self.prompt = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .videoEdit)
    }
}

/// `POST /v1/flux-tools/video-upscale-v1`
public struct VideoUpscaleRequest: Encodable, Sendable, Equatable {
    public var inputVideo: String
    public var prompt: String?
    /// 0 = fiel al original, 1 = añade detalle (cuesta ~40 % más y puede alterar caras y textos).
    public var creativity: Int
    public var upscaleFactor: Double
    public var safetyTolerance: Int

    enum CodingKeys: String, CodingKey {
        case prompt, creativity
        case inputVideo = "input_video"
        case upscaleFactor = "upscale_factor"
        case safetyTolerance = "safety_tolerance"
    }

    public init(inputVideo: String, prompt: String = "", creativity: Int = 0, upscaleFactor: Double = 2,
                safetyTolerance: Int = SafetyTolerance.defaultValue) {
        self.inputVideo = inputVideo
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.prompt = p.isEmpty ? nil : p
        self.creativity = creativity >= 1 ? 1 : 0
        self.upscaleFactor = min(3, max(1.5, upscaleFactor))
        self.safetyTolerance = SafetyTolerance.clamp(safetyTolerance, for: .videoUpscale)
    }
}
