import AppKit
import FluxCore
import SwiftUI

/// Selector de una imagen del Historial.
struct HistoryPicker: View {
    @EnvironmentObject private var history: HistoryStore
    let completion: (URL?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Elige una imagen del historial").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Cancelar") { completion(nil) }.keyboardShortcut(.cancelAction)
            }
            .padding(18)
            Divider()
            let images = history.items.filter { !$0.isVideo }
            if images.isEmpty {
                Text(history.isLoading ? "Cargando…" : "Todavía no hay imágenes en el historial.")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(images) { item in
                            PickerThumb(url: item.fileURL)
                                .onTapGesture { completion(item.fileURL) }
                                .help(item.record.prompt)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(width: 760, height: 560)
        .background(Theme.background)
        .onAppear { history.reload() }
        .preferredColorScheme(.light)
    }
}

private struct PickerThumb: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { Image(nsImage: image).resizable().scaledToFill() } else { ShimmerView() }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .task(id: url) { image = await ThumbnailLoader.load(url, maxPixelSize: 400) }
    }
}


/// Barra superior de Editar con precisión (estilo FLUX Tools).
struct EditToolbar: View {
    @EnvironmentObject private var model: PreciseEditModel
    @Binding var confirmReset: Bool

    var body: some View {
        HStack(spacing: 2) {
            ToolTextButton(icon: "plus.square", title: "Añadir región") { model.addDefaultRegion() }
                .disabled(model.compareMode)
            ToolTextButton(icon: "square.dashed", title: model.showRegions ? "Ocultar regiones" : "Mostrar regiones",
                           isActive: !model.showRegions) { model.showRegions.toggle() }
            ToolTextButton(icon: "xmark.square", title: "Borrar todas") { model.clearRegions() }
                .disabled(model.regions.isEmpty)
            divider
            ToolTextButton(icon: "arrow.down.to.line", title: "Descargar") { download() }
            ToolTextButton(icon: "arrow.counterclockwise", title: "Empezar de nuevo") { confirmReset = true }
                .help("Quita regiones y versiones y vuelve a la imagen original")

            if model.parentOfCurrent != nil {
                divider
                ToolTextButton(icon: "rectangle.split.2x1", title: "Antes / Después", isActive: model.compareMode) {
                    model.compareMode.toggle()
                }
            }

            if model.versions.count > 1 {
                divider
                Button { model.goToVersion(model.currentIndex - 1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .disabled(model.currentIndex == 0)
                Menu {
                    ForEach(Array(model.versions.enumerated()), id: \.element.id) { index, version in
                        Button(index == 0 ? "Original" : "Versión \(index + 1) (de la \((version.parentIndex ?? 0) + 1))") {
                            model.goToVersion(index)
                        }
                    }
                } label: {
                    Text(model.currentIndex == 0 ? "ORIGINAL" : "VERSIÓN \(model.currentIndex + 1)/\(model.versions.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button { model.goToVersion(model.currentIndex + 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.plain)
                    .disabled(model.currentIndex >= model.versions.count - 1)
                    .padding(.trailing, 6)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .surfaceStyle(cornerRadius: 14)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 20).padding(.horizontal, 6)
    }

    private func download() {
        guard let version = model.current else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = version.fileURL.lastPathComponent
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: version.fileURL, to: dest)
        }
    }
}
