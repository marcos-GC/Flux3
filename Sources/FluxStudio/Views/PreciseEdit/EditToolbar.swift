import AppKit
import FluxCore
import SwiftUI

/// Barra de regiones de Editar con precisión (estilo FLUX Tools), encima de la caja del prompt.
struct EditToolbar: View {
    @EnvironmentObject private var model: PreciseEditModel
    @EnvironmentObject private var state: AppState
    @ObservedObject var viewer: ViewerZoom
    @Binding var confirmReset: Bool

    /// Hay una imagen anterior a la que volver: la primera versión de esta sesión
    /// o, si la imagen abierta ya era un resultado, su original guardado.
    private var canGoToOriginal: Bool {
        model.currentIndex != 0 || state.original(of: model.current?.fileURL) != nil
    }

    private func goToOriginal() {
        if let first = model.versions.first?.fileURL, let original = state.original(of: first) {
            // La imagen abierta ya salía de otra edición: se abre su original.
            state.focus(original, tool: .edit)
        } else {
            model.goToVersion(0)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if canGoToOriginal {
                ToolIconButton(icon: "arrow.uturn.backward",
                               help: "Original: volver a la imagen antes de editarla (⌘↑). Las ediciones siguen en la tira.") {
                    goToOriginal()
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                divider
            }
            ToolIconButton(icon: "plus.square", help: "Añadir región") { model.addDefaultRegion() }
                .disabled(model.compareMode || viewer.isCropping)
            ToolIconButton(icon: model.showRegions ? "square.dashed" : "eye.slash",
                           help: model.showRegions ? "Ocultar regiones" : "Mostrar regiones",
                           isActive: !model.showRegions) { model.showRegions.toggle() }
            ToolIconButton(icon: "xmark.square", help: "Quitar todas las regiones") { model.clearRegions() }
                .disabled(model.regions.isEmpty)
            divider
            ToolIconButton(icon: "arrow.down.to.line", help: "Descargar esta versión") { download() }
            ToolIconButton(icon: "arrow.counterclockwise",
                           help: "Empezar de nuevo: quita regiones y versiones y vuelve a la imagen original") {
                confirmReset = true
            }
            divider
            ToolIconButton(icon: "rectangle.split.2x1",
                           help: model.parentOfCurrent == nil
                               ? "Antes / Después: esta versión no sale de otra todavía"
                               : "Antes / Después: comparar con la versión de la que sale",
                           isActive: model.compareMode) {
                viewer.cancelCrop()
                model.compareMode.toggle()
            }
            .disabled(model.parentOfCurrent == nil)
            ToolIconButton(icon: "crop", help: "Recortar: la versión recortada se guarda como imagen nueva",
                           isActive: viewer.isCropping) {
                if viewer.isCropping {
                    viewer.cancelCrop()
                } else {
                    model.compareMode = false
                    model.selectedRegionID = nil
                    viewer.startCrop()
                }
            }
            .disabled(model.current == nil)
            if viewer.isCropping, let version = model.current {
                CropActionButtons(viewer: viewer, imageAspect: aspect(version.pixelSize)) {
                    guard let rect = viewer.cropRect else { return }
                    viewer.cancelCrop()
                    state.saveCrop(of: version.fileURL, rect: rect)
                }
            }

            if model.versions.count > 1 {
                divider
                ToolIconButton(icon: "chevron.left", help: "Versión anterior") {
                    model.goToVersion(model.currentIndex - 1)
                }
                .disabled(model.currentIndex == 0)
                Menu {
                    ForEach(Array(model.versions.enumerated()), id: \.element.id) { index, version in
                        Button(index == 0 ? "Original" : "Versión \(index + 1) (de la \((version.parentIndex ?? 0) + 1))") {
                            model.goToVersion(index)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack")
                            .font(.system(size: 13))
                        Text("\(model.currentIndex + 1)/\(model.versions.count)")
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .frame(height: 28)
                    .padding(.horizontal, 4)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(model.currentIndex == 0 ? "Versiones: estás en la original" : "Versiones: estás en la \(model.currentIndex + 1) de \(model.versions.count)")
                ToolIconButton(icon: "chevron.right", help: "Versión siguiente") {
                    model.goToVersion(model.currentIndex + 1)
                }
                .disabled(model.currentIndex >= model.versions.count - 1)
            }

            Spacer(minLength: 8)
            ZoomButtons(zoom: $model.zoom, pan: $model.pan)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .surfaceStyle(cornerRadius: 14)
        // Mismo ancho que la caja de abajo.
        .frame(maxWidth: 860)
        .padding(.horizontal, 28)
    }

    private func aspect(_ size: CGSize) -> CGFloat {
        size.height > 0 ? size.width / size.height : 1
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 18).padding(.horizontal, 4)
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
