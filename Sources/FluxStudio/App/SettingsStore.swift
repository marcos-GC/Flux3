import FluxCore
import Foundation

enum OutputFormat: String, CaseIterable, Identifiable {
    case jpeg, png, webp
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// Preferencias guardadas en UserDefaults. La API key NO va aquí: va al Llavero.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var region: APIRegion {
        didSet { defaults.set(region.rawValue, forKey: Keys.region) }
    }
    @Published var outputFolder: URL {
        didSet { defaults.set(outputFolder.path, forKey: Keys.outputFolder) }
    }
    @Published var defaultFormat: OutputFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: Keys.format) }
    }
    @Published var defaultSafety: Int {
        didSet { defaults.set(defaultSafety, forKey: Keys.safety) }
    }
    @Published var defaultImageCount: Int {
        didSet { defaults.set(defaultImageCount, forKey: Keys.count) }
    }
    @Published private(set) var hasAPIKey: Bool

    private enum Keys {
        static let region = "region"
        static let outputFolder = "outputFolder"
        static let format = "defaultFormat"
        static let safety = "defaultSafety"
        static let count = "defaultImageCount"
    }

    static var standardOutputFolder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return pictures.appendingPathComponent("FLUX Studio", isDirectory: true)
    }

    init() {
        region = APIRegion(rawValue: defaults.string(forKey: Keys.region) ?? "") ?? .eu
        if let path = defaults.string(forKey: Keys.outputFolder), !path.isEmpty {
            outputFolder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            outputFolder = Self.standardOutputFolder
        }
        defaultFormat = OutputFormat(rawValue: defaults.string(forKey: Keys.format) ?? "") ?? .jpeg
        defaultSafety = defaults.object(forKey: Keys.safety) as? Int ?? SafetyTolerance.defaultValue
        let count = defaults.integer(forKey: Keys.count)
        defaultImageCount = (1...4).contains(count) ? count : 1
        // Al abrir la app solo se comprueba que exista la clave, sin leerla:
        // así macOS no pide la contraseña del Llavero al arrancar.
        hasAPIKey = KeychainService.hasAPIKey()
    }

    /// La clave se lee del Llavero una sola vez por sesión y se guarda en memoria (nunca en disco).
    private var cachedAPIKey: String?

    func saveAPIKey(_ key: String) throws {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try KeychainService.saveAPIKey(clean)
        cachedAPIKey = clean
        hasAPIKey = true
    }

    func deleteAPIKey() {
        KeychainService.deleteAPIKey()
        cachedAPIKey = nil
        hasAPIKey = false
    }

    /// Cliente listo para usar, o error si falta la clave.
    func makeClient() throws -> BFLClient {
        if cachedAPIKey == nil {
            cachedAPIKey = KeychainService.loadAPIKey()
        }
        guard let key = cachedAPIKey, !key.isEmpty else { throw BFLError.missingAPIKey }
        return BFLClient(apiKey: key, region: region)
    }
}
