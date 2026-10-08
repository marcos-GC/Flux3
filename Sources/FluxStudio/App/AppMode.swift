import Foundation

/// Modos de la barra lateral.
enum AppMode: String, CaseIterable, Identifiable {
    case generate, preciseEdit, outpaint, erase, tryOn, deblur, video, history, settings

    var id: String { rawValue }

    static let tools: [AppMode] = [.generate]

    var title: String {
        switch self {
        case .generate: return "Estudio"
        case .preciseEdit: return "Editar con precisión"
        case .outpaint: return "Outpainting"
        case .erase: return "Borrar"
        case .tryOn: return "Probador virtual"
        case .deblur: return "Deblur"
        case .video: return "Vídeo"
        case .history: return "Historial"
        case .settings: return "Ajustes"
        }
    }

    var icon: String {
        switch self {
        case .generate: return "sparkles"
        case .preciseEdit: return "selection.pin.in.out"
        case .outpaint: return "arrow.up.left.and.arrow.down.right"
        case .erase: return "eraser"
        case .tryOn: return "tshirt"
        case .deblur: return "camera.aperture"
        case .video: return "film"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    /// Fase del plan en la que llega cada modo.
    var plannedPhase: Int {
        switch self {
        case .generate, .settings: return 1
        case .history: return 2
        case .preciseEdit: return 3
        case .outpaint, .erase, .tryOn, .deblur: return 4
        case .video: return 5
        }
    }
}
