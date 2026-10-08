import AppKit
import FluxCore
import SwiftUI

/// "Editar con precisión": réplica de flux-tools.bfl.ai/precise-editing.
struct PreciseEditView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var model: PreciseEditModel
    @State private var showPrompt = false
    @State private var confirmReset = false

    var body: some View {
        Group {
            if model.current == nil {
                PreciseEditStartView()
            } else {
                ZStack {
                    EditCanvas()
                    VStack(spacing: 0) {
                        EditToolbar(showPrompt: $showPrompt, confirmReset: $confirmReset)
                            .padding(.top, 18)
                        Spacer()
                        if showPrompt {
                            PromptPanel()
                                .padding(.bottom, 8)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        PreciseEditBar(showPrompt: $showPrompt)
                            .padding(.bottom, 22)
                    }
                }
            }
        }
        .onAppear(perform: takeHandoff)
        .onChange(of: state.handoff) { takeHandoff() }
        .animation(.easeOut(duration: 0.18), value: showPrompt)
        .confirmationDialog("¿Empezar de nuevo?", isPresented: $confirmReset) {
            Button("Empezar de nuevo", role: .destructive) { model.reset() }
        } message: {
            Text("Se quitan la imagen, las regiones y las versiones de esta sesión. Los resultados ya guardados siguen en el Historial.")
        }
    }

    private func takeHandoff() {
        guard let handoff = state.handoff, handoff.mode == .preciseEdit else { return }
        model.load(handoff.fileURL)
        state.handoff = nil
    }
}

// MARK: - Pantalla inicial

private struct PreciseEditStartView: View {
    @EnvironmentObject private var model: PreciseEditModel
    @EnvironmentObject private var history: HistoryStore
    @State private var isDropTarget = false
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Editar con precisión")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Dibuja regiones sobre la imagen y di qué debe cambiar en cada una.")
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: 14) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Button {
                    if let url = chooseImages(allowsMultiple: false).first { model.load(url) }
                } label: {
                    Text("Subir imagen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Theme.action))
                }
                .buttonStyle(.plain)
                Text("o arrastra una imagen aquí")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(width: 520, height: 260)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isDropTarget ? Theme.region.opacity(0.08) : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isDropTarget ? Theme.region : Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: ReferenceImage.isSupported) else { return false }
                model.load(url)
                return true
            } isTargeted: { isDropTarget = $0 }

            Button { showHistory = true } label: {
                Chip(icon: "clock.arrow.circlepath", text: "Usar una imagen del historial")
            }
            .buttonStyle(.plain)

            if let error = model.loadError {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showHistory) {
            HistoryPicker { url in
                showHistory = false
                if let url { model.load(url) }
            }
            .environmentObject(history)
        }
    }
}

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

// MARK: - Barra superior

private struct EditToolbar: View {
    @EnvironmentObject private var model: PreciseEditModel
    @Binding var showPrompt: Bool
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
