import AppKit
import FluxCore
import SwiftUI

/// Acciones comunes sobre un resultado (menú contextual del feed y del Historial).
struct ResultActions: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    let fileURL: URL
    var record: GenerationRecord?
    var prompt: String?
    var expandedPrompt: String?

    var body: some View {
        if !VideoModel.isVideo(fileURL) {
            Button("Editar esta imagen") { state.send(fileURL, to: .preciseEdit) }
            Button("Usar como referencia") { state.useAsReference(fileURL) }
        }
        if history.items.contains(where: { $0.fileURL == fileURL }) {
            Button(history.isFavorite(fileURL) ? "Quitar de favoritas" : "Marcar como favorita") {
                history.toggleFavorite(fileURL)
            }
        }
        Divider()
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

/// Corazón amarillo para marcar favoritas: siempre visible si está marcada;
/// si no, solo aparece al pasar el ratón (`visibleWhenOff`).
struct FavoriteButton: View {
    @EnvironmentObject private var history: HistoryStore
    let fileURL: URL
    var visibleWhenOff = false
    var size: CGFloat = 11

    var body: some View {
        let on = history.isFavorite(fileURL)
        if on || visibleWhenOff {
            Button { history.toggleFavorite(fileURL) } label: {
                Image(systemName: on ? "heart.fill" : "heart")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(on ? Theme.favorite : Color.white)
                    .frame(width: size + 11, height: size + 11)
                    .background(Circle().fill(on ? Color.white : Color.black.opacity(0.45)))
                    .overlay(Circle().strokeBorder(on ? Theme.favorite : Color.clear, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(on ? "Quitar de favoritas" : "Marcar como favorita")
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

/// Copia el archivo y la imagen: se puede pegar con ⌘V en la app, en el Finder o en otras apps.
@MainActor
func copyImage(_ url: URL) {
    Clipboard.copy(url)
}

func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
