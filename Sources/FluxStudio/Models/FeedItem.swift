import AppKit
import FluxCore
import Foundation

/// Un hueco del grid de resultados (una petición a BFL).
struct ResultSlot: Identifiable {
    enum Phase: Equatable {
        case submitting
        case running(BFLStatus)
        case downloading
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    var phase: Phase = .submitting
    var taskID: String?
    var cost: Double?
    var fileURL: URL?
    var image: NSImage?
    var expandedPrompt: String?

    var isActive: Bool {
        switch phase {
        case .submitting, .running, .downloading: return true
        default: return false
        }
    }

    var statusText: String {
        switch phase {
        case .submitting: return "Enviando"
        case .running(let s): return s.spanishLabel
        case .downloading: return "Descargando"
        case .done: return "Listo"
        case .failed: return "Error"
        case .cancelled: return "Cancelado"
        }
    }
}

/// Una fila del feed: el prompt a la izquierda y sus resultados a la derecha.
struct FeedItem: Identifiable {
    let id = UUID()
    let prompt: String
    let modelName: String
    let aspectRatio: Double
    let createdAt = Date()
    var slots: [ResultSlot]

    var isRunning: Bool { slots.contains(where: \.isActive) }
    var totalCost: Double { slots.compactMap(\.cost).reduce(0, +) }
}

/// Parámetros elegidos en la barra de prompt para FLUX 3 Image.
struct ImageParams {
    var aspectRatio = "auto"
    var resolution = "1k"
    var count = 1
    var safety = SafetyTolerance.defaultValue
    var grounding = true
}
