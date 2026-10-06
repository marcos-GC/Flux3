import Foundation

/// Reglas del parámetro `safety_tolerance` (0 = más estricto).
public enum SafetyTolerance {
    public static let defaultValue = 2

    public static let tooltip = "Controla lo estricta que es la moderación de contenido de BFL con las entradas y salidas. No cambia el estilo ni la creatividad de la imagen."

    /// Rango admitido por cada endpoint.
    public static func range(for endpoint: BFLEndpoint) -> ClosedRange<Int> {
        switch endpoint {
        case .flux3Image, .flux3Video, .videoEdit, .videoUpscale: return 0...4
        case .outpaint, .erase, .deblur, .vto: return 0...5
        }
    }

    /// Ajusta un valor al rango del endpoint (si no cabe, al máximo o mínimo permitido).
    public static func clamp(_ value: Int, for endpoint: BFLEndpoint) -> Int {
        let r = range(for: endpoint)
        return min(max(value, r.lowerBound), r.upperBound)
    }

    /// Etiqueta en español para un valor, según el máximo del endpoint.
    public static func label(for value: Int, maximum: Int) -> String {
        switch value {
        case ...0: return "Muy estricto"
        case 1: return "Estricto"
        case 2: return "Por defecto"
        case _ where value >= maximum: return "Muy permisivo"
        case 3: return "Permisivo"
        default: return "Bastante permisivo"
        }
    }
}
