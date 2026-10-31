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
        if !VideoModel.isVideo(fileURL) {
            Button("Editar esta imagen") { state.send(fileURL, to: .preciseEdit) }
            Button("Usar como referencia") { state.useAsReference(fileURL) }
            Divider()
        }
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
        Menu("Enviar a") {
            SendToButtons(fileURL: fileURL)
        }
    }
}

/// Opciones de «Enviar a», con los mismos nombres que la barra lateral.
struct SendToButtons: View {
    @EnvironmentObject private var state: AppState
    let fileURL: URL
    var onSend: () -> Void = {}

    var body: some View {
        if VideoModel.isVideo(fileURL) {
            Button("Vídeo (continuar, editar o escalar)") {
                onSend()
                state.send(fileURL, to: .video)
            }
        } else {
            imageTools
        }
    }

    @ViewBuilder
    private var imageTools: some View {
        ForEach([AppMode.preciseEdit, .erase, .outpaint, .deblur, .tryOn], id: \.self) { mode in
            Button(mode == .tryOn ? "\(mode.title) (como persona)" : mode.title) {
                onSend()
                state.send(fileURL, to: mode)
            }
        }
        Button("Vídeo (imagen a vídeo)") {
            onSend()
            state.send(fileURL, to: .video)
        }
    }
}

/// Lo que se arrastra desde una miniatura o una imagen: la URL del archivo.
/// Así el Estudio (y el Finder) reciben el archivo original con su extensión; con
/// `NSItemProvider(contentsOf:)` llegaba una copia temporal sin extensión y el Estudio
/// avisaba de «Archivo no compatible».
func fileDragProvider(_ url: URL) -> NSItemProvider {
    let provider = NSItemProvider(object: url as NSURL)
    provider.suggestedName = url.lastPathComponent
    return provider
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
