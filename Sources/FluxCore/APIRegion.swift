import Foundation

/// Región de la API de BFL. Por defecto EU.
public enum APIRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case eu, us, global

    public var id: String { rawValue }

    public var baseURL: URL {
        switch self {
        case .eu: return URL(string: "https://api.eu.bfl.ai")!
        case .us: return URL(string: "https://api.us.bfl.ai")!
        case .global: return URL(string: "https://api.bfl.ai")!
        }
    }

    public var displayName: String {
        switch self {
        case .eu: return "Europa (EU)"
        case .us: return "Estados Unidos (US)"
        case .global: return "Global"
        }
    }
}
