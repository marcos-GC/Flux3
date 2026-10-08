import AppKit
import FluxCore
import SwiftUI

/// Acciones comunes sobre un resultado (menú contextual del feed y del Historial).
struct ResultActions: View {
    @EnvironmentObject private var state: AppState
    let fileURL: URL
    var record: GenerationRecord?
    var prompt: String?
    var expandedPrompt: String?

    var body: some View {
        Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
        Button("Abrir") { NSWorkspace.shared.open(fileURL) }
        Button("Copiar imagen") { copyImage(fileURL) }
        if let text = prompt ?? record?.prompt {
            Button("Copiar prompt") { copyText(text) }
        }
        if let expanded = expandedPrompt ?? record?.expandedPrompt {
            Button("Copiar prompt expandido") { copyText(expanded) }
        }
        Divider()
        if let record {
            Button("Reutilizar prompt y parámetros") { state.reuse(record) }
        }
        Button("Usar como referencia") { state.useAsReference(fileURL) }
        Menu("Enviar a") {
            Button("Editar con precisión") { state.send(fileURL, to: .preciseEdit) }
            Button("Outpainting") { state.send(fileURL, to: .outpaint) }
            Button("Borrar") { state.send(fileURL, to: .erase) }
            Button("Imagen a vídeo") { state.send(fileURL, to: .video) }
        }
    }
}

func copyImage(_ url: URL) {
    guard let image = NSImage(contentsOf: url) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
