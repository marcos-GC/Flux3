import Foundation

/// Endpoints de BFL que usa la app.
public enum BFLEndpoint: String, CaseIterable, Codable, Sendable {
    case flux3Image
    case flux3Video
    case videoEdit
    case videoUpscale
    case outpaint
    case erase
    case deblur
    case vto

    public var path: String {
        switch self {
        case .flux3Image: return "v1/flux-3-image"
        case .flux3Video: return "v1/flux-3-video"
        case .videoEdit: return "v1/flux-tools/video-edit-v1"
        case .videoUpscale: return "v1/flux-tools/video-upscale-v1"
        case .outpaint: return "v1/flux-tools/outpainting-v1"
        case .erase: return "v1/flux-tools/erase-v1"
        case .deblur: return "v1/flux-tools/deblur-v1"
        case .vto: return "v1/flux-tools/vto-v2"
        }
    }

    public var displayName: String {
        switch self {
        case .flux3Image: return "FLUX 3 Image"
        case .flux3Video: return "FLUX 3 Video"
        case .videoEdit: return "FLUX Video Edit"
        case .videoUpscale: return "FLUX Video Upscale"
        case .outpaint: return "Outpainting"
        case .erase: return "Erase"
        case .deblur: return "Deblur"
        case .vto: return "Virtual Try-On"
        }
    }

    /// Prefijo para los nombres de archivo guardados.
    public var filePrefix: String {
        switch self {
        case .flux3Image: return "flux3-image"
        case .flux3Video: return "flux3-video"
        case .videoEdit: return "video-edit"
        case .videoUpscale: return "video-upscale"
        case .outpaint: return "outpaint"
        case .erase: return "erase"
        case .deblur: return "deblur"
        case .vto: return "vto"
        }
    }

    /// Los vídeos tardan minutos: BFL recomienda consultar cada ~6 s.
    public var pollInterval: TimeInterval {
        isVideo ? 6 : 1
    }

    public var pollTimeout: TimeInterval {
        isVideo ? 90 * 60 : 15 * 60
    }

    public var isVideo: Bool {
        switch self {
        case .flux3Video, .videoEdit, .videoUpscale: return true
        default: return false
        }
    }
}
