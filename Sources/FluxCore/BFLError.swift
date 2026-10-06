import Foundation

/// Errores de la API traducidos a mensajes claros en español.
public enum BFLError: LocalizedError, Equatable, Sendable {
    public enum Phase: Sendable { case submit, poll, download, other }

    case missingAPIKey
    case http(status: Int, detail: String?, phase: Phase)
    case taskFailed(status: BFLStatus, detail: String?)
    case timeout(minutes: Int)
    case invalidResponse(String)
    case network(String)
    case noResult

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Falta la API key. Pégala en Ajustes y pulsa «Guardar en el Llavero»."

        case let .http(status, detail, phase):
            let extra = detail.flatMap { $0.isEmpty ? nil : " Detalle: \($0)" } ?? ""
            switch status {
            case 401, 403:
                return "La API key no es válida o no tiene permisos. Revísala en Ajustes." + extra
            case 402:
                return "No te quedan créditos en BFL. Recarga en dashboard.bfl.ai y vuelve a intentarlo."
            case 404 where phase == .download:
                return "El archivo del resultado ya no existe (los enlaces de BFL caducan en minutos)."
            case 404:
                return "BFL no reconoce esta ruta o tarea (404)." + extra
            case 413:
                return "El archivo enviado es demasiado grande para BFL. Usa una imagen o vídeo más pequeño."
            case 422:
                return "BFL ha rechazado algún parámetro de la petición." + extra
            case 429 where phase == .submit:
                return "Has llegado al límite de peticiones simultáneas de tu cuenta. No se ha creado ninguna tarea ni se ha cobrado nada: espera a que terminen otras y vuelve a intentarlo."
            case 429:
                return "BFL pide que esperemos (límite de peticiones). La tarea sigue en marcha."
            case 500...599:
                return "Error temporal en los servidores de BFL (\(status)). Inténtalo de nuevo en unos minutos."
            default:
                return "Error HTTP \(status) de BFL." + extra
            }

        case let .taskFailed(status, detail):
            let extra = detail.flatMap { $0.isEmpty ? nil : " Detalle: \($0)" } ?? ""
            switch status {
            case .requestModerated:
                return "Moderado: BFL ha bloqueado la petición (prompt o imágenes de entrada). Prueba a subir la tolerancia de seguridad o cambia el prompt."
            case .contentModerated:
                return "Moderado: BFL ha bloqueado el resultado generado. Prueba a subir la tolerancia de seguridad o cambia el prompt."
            case .taskNotFound:
                return "BFL no encuentra la tarea: puede haber caducado o haberse enviado a otra región."
            default:
                return "BFL no ha podido completar la tarea." + extra
            }

        case .timeout(let minutes):
            return "La tarea ha tardado más de \(minutes) minutos y se ha dejado de esperar."
        case .invalidResponse(let what):
            return "Respuesta inesperada de BFL: \(what)"
        case .network(let what):
            return "Problema de conexión: \(what). Comprueba tu Internet."
        case .noResult:
            return "BFL ha terminado pero no ha devuelto ningún archivo."
        }
    }
}
