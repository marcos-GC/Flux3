import Foundation

/// Valor JSON genérico, para guardar parámetros y leer respuestas imprevistas.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Valor JSON no reconocido")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }

    /// Convierte cualquier valor `Encodable` en `JSONValue`.
    public init<T: Encodable>(encoding value: T) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    /// Texto legible (para mensajes de error).
    public var readableText: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return ""
        case .array(let a): return a.map(\.readableText).filter { !$0.isEmpty }.joined(separator: "; ")
        case .object(let o):
            // Formato típico de error de validación: {"loc": [...], "msg": "..."}
            if let msg = o["msg"]?.readableText, !msg.isEmpty {
                if let loc = o["loc"], case .array(let parts) = loc {
                    let field = parts.map(\.readableText).filter { $0 != "body" }.joined(separator: ".")
                    return field.isEmpty ? msg : "\(field): \(msg)"
                }
                return msg
            }
            for key in ["detail", "message", "error"] {
                if let v = o[key]?.readableText, !v.isEmpty { return v }
            }
            return o.keys.sorted().map { "\($0): \(o[$0]!.readableText)" }.joined(separator: ", ")
        }
    }

    /// Sustituye cadenas enormes (imágenes/vídeos en base64) por un marcador,
    /// para guardar los parámetros en el .json sin ocupar megas.
    public func strippingLargeStrings(limit: Int = 2048) -> JSONValue {
        switch self {
        case .string(let s) where s.count > limit && !s.hasPrefix("http"):
            return .string("<archivo en base64 omitido (\(s.count) caracteres)>")
        case .array(let a): return .array(a.map { $0.strippingLargeStrings(limit: limit) })
        case .object(let o): return .object(o.mapValues { $0.strippingLargeStrings(limit: limit) })
        default: return self
        }
    }
}
