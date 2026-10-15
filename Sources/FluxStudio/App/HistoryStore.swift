import AppKit
import FluxCore
import Foundation

/// Lista de resultados guardados en la carpeta de salida.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [StoredResult] = []
    @Published private(set) var isLoading = false
    /// Lo que se ha generado o abierto desde el Historial en esta sesión (la tira del Estudio).
    @Published private(set) var sessionURLs: Set<URL> = []

    private let settings: SettingsStore
    private var loadedFolder: URL?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// Vuelve a leer la carpeta (si `force` o si ha cambiado la carpeta de salida).
    func reload(force: Bool = false) {
        let base = settings.outputFolder
        guard force || loadedFolder != base else { return }
        isLoading = true
        Task {
            let loaded = await Task.detached(priority: .userInitiated) { ResultStore.loadAll(base: base) }.value
            items = loaded
            loadedFolder = base
            isLoading = false
        }
    }

    func add(_ result: StoredResult) {
        items.insert(result, at: 0)
        sessionURLs.insert(result.fileURL)
    }

    /// Añade a la tira de esta sesión un resultado guardado (p. ej. abierto desde el Historial).
    func includeInSession(_ url: URL) {
        guard !sessionURLs.contains(url), items.contains(where: { $0.fileURL == url }) else { return }
        sessionURLs.insert(url)
    }

    /// Resultados de esta sesión, lo más reciente arriba.
    var sessionItems: [StoredResult] {
        items.filter { sessionURLs.contains($0.fileURL) }
    }

    /// Mueve el archivo y su .json a la Papelera.
    func moveToTrash(_ result: StoredResult) {
        NSWorkspace.shared.recycle([result.fileURL, result.metadataURL]) { _, _ in }
        items.removeAll { $0.id == result.id }
    }

    /// Nombres de modelo presentes, para el filtro.
    var models: [String] {
        Array(Set(items.map { ToolNames.display($0.record.model) })).sorted()
    }
}
