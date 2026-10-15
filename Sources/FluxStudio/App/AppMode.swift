import Foundation

/// Modos de la barra lateral.
enum AppMode: String, CaseIterable, Identifiable {
    case generate, preciseEdit, outpaint, erase, tryOn, deblur, video, history, settings

    var id: String { rawValue }

    static let tools: [AppMode] = [.generate]

    var title: String {
        switch self {
        case .generate: return "Estudio"
        case .preciseEdit: return "Editar"
        case .outpaint: return "Ampliar"
        case .erase: return "Borrar"
        case .tryOn: return "Probador"
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
}

/// Nombres de herramienta que se guardaban en versiones anteriores, para mostrarlos
/// con el vocabulario actual (el mismo de la barra lateral).
enum ToolNames {
    private static let legacy = [
        "Editar con precisión": "Editar",
        "Outpainting": "Ampliar",
        "Probador virtual": "Probador",
    ]

    static func display(_ model: String) -> String {
        legacy[model] ?? model
    }
}
