import AppKit
import FluxCore
import SwiftUI
import UniformTypeIdentifiers

/// Copiar y pegar imágenes con ⌘C / ⌘V dentro de la app.
///
/// - ⌘C (sin estar escribiendo): copia la imagen seleccionada (el archivo y la imagen),
///   así se puede pegar aquí, en el Finder o en otras apps.
/// - ⌘V: si en el portapapeles hay una imagen (copiada aquí, en el Finder o en otra app,
///   p. ej. una captura), pregunta si se quiere editar o usar como referencia.
///   Si se está escribiendo y hay texto, ⌘V pega el texto como siempre.
@MainActor
enum Clipboard {
    /// `changeCount` del portapapeles tras la última copia hecha desde la app. Si sigue igual,
    /// lo que hay es nuestra imagen (aunque también lleve la ruta como texto).
    private static var ownCopyChangeCount: Int?

    /// Copia un archivo (y la imagen, si lo es) al portapapeles.
    static func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var objects: [NSPasteboardWriting] = [url as NSURL]
        if !VideoModel.isVideo(url), let image = NSImage(contentsOf: url) {
            objects.append(image)
        }
        pasteboard.writeObjects(objects)
        ownCopyChangeCount = pasteboard.changeCount
    }

    private static var isOwnCopy: Bool {
        ownCopyChangeCount == NSPasteboard.general.changeCount
    }

    private static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static var hasText: Bool {
        NSPasteboard.general.availableType(from: [.string]) != nil
    }

    /// Imágenes del portapapeles como archivos. Si es una imagen sin archivo (una captura,
    /// una imagen copiada del navegador…), se guarda en «<carpeta de salida>/Pegadas».
    static func imageURLs(saveFolder: URL) -> [URL] {
        let pasteboard = NSPasteboard.general
        let files = fileURLs(pasteboard)
        // Archivos copiados (del Finder o de aquí): solo valen los que son imágenes.
        if !files.isEmpty { return files.filter(ReferenceImage.isSupported) }

        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return [] }
        let folder = saveFolder.appendingPathComponent("Pegadas", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let url = folder.appendingPathComponent("pegada_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(4)).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            return [url]
        } catch {
            return []
        }
    }

    static var hasImage: Bool {
        let pasteboard = NSPasteboard.general
        let files = fileURLs(pasteboard)
        if !files.isEmpty { return files.contains(where: ReferenceImage.isSupported) }
        return NSImage.canInit(with: pasteboard)
    }

    // MARK: Atajos

    /// Escucha ⌘C y ⌘V en la ventana. Devuelve el monitor para poder quitarlo.
    static func installMonitor(state: AppState) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed: Bool = MainActor.assumeIsolated { handle(event, state: state) }
            return consumed ? nil : event
        }
    }

    private static func handle(_ event: NSEvent, state: AppState) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        // Con una ventana de ajustes, un diálogo o un menú delante, no se toca nada.
        guard NSApp.keyWindow?.attachedSheet == nil, state.pendingPaste.isEmpty else { return false }
        let editingText = NSApp.keyWindow?.firstResponder is NSText

        switch key {
        case "c" where !editingText:
            guard state.mode != .settings, state.mode != .history, let url = state.focusedURL else { return false }
            copy(url)
            return true
        case "v":
            // Escribiendo y con texto copiado: pegar el texto como siempre.
            // (Salvo que sea una imagen copiada aquí, que también lleva su ruta como texto.)
            if editingText && hasText && !isOwnCopy { return false }
            guard hasImage else { return false }
            let urls = imageURLs(saveFolder: state.settings.outputFolder)
            guard !urls.isEmpty else { return false }
            state.pendingPaste = urls
            return true
        default:
            return false
        }
    }
}

extension AppState {
    /// Imágenes que llegan de fuera (arrastradas o pegadas): abrir en Editar o usar como referencia.
    func receive(_ urls: [URL], as zone: StudioDropZone) {
        let images = urls.filter(ReferenceImage.isSupported)
        guard !images.isEmpty else {
            alert = AppAlert(title: "Archivo no compatible", message: "Solo se pueden usar imágenes (JPEG, PNG, WebP, HEIC…).")
            return
        }
        switch zone {
        case .edit:
            focus(images[0], tool: .edit)
        case .reference:
            addReferences(images)
            selectTool(.generate)
        }
    }
}
