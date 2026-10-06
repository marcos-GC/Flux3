import Foundation

/// Estado de una tarea según la `polling_url`. Se guarda el texto exacto de BFL.
public struct BFLStatus: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public static let pending = BFLStatus(rawValue: "Pending")
    public static let reasoning = BFLStatus(rawValue: "Reasoning")
    public static let generating = BFLStatus(rawValue: "Generating")
    public static let ready = BFLStatus(rawValue: "Ready")
    public static let error = BFLStatus(rawValue: "Error")
    public static let requestModerated = BFLStatus(rawValue: "Request Moderated")
    public static let contentModerated = BFLStatus(rawValue: "Content Moderated")
    public static let taskNotFound = BFLStatus(rawValue: "Task not found")

    public enum Kind: Sendable { case running, success, failure }

    public var kind: Kind {
        switch self {
        case .ready: return .success
        case .error, .requestModerated, .contentModerated, .taskNotFound: return .failure
        default: return .running // Pending, Reasoning, Generating y cualquier estado nuevo
        }
    }

    public var spanishLabel: String {
        switch self {
        case .pending: return "En cola"
        case .reasoning: return "Razonando"
        case .generating: return "Generando"
        case .ready: return "Listo"
        case .error: return "Error"
        case .requestModerated: return "Entrada moderada"
        case .contentModerated: return "Resultado moderado"
        case .taskNotFound: return "Tarea no encontrada"
        default: return rawValue
        }
    }

    public var description: String { rawValue }
}
