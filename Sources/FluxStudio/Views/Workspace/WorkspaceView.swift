import AppKit
import AVKit
import FluxCore
import SwiftUI

/// Pantalla principal (Estudio): imagen seleccionada en grande, herramientas abajo
/// y tira de resultados a la derecha. Todo se hace sobre la imagen seleccionada.
struct WorkspaceView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var preciseEdit: PreciseEditModel
    @State private var showPrompt = false
    @State private var confirmReset = false
    @State private var isDropTarget = false

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if state.tool == .edit && state.focusedURL != nil {
                    editLayout
                } else {
                    standardLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.region, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(Theme.region.opacity(0.05))
                        .overlay(
                            Label("Suelta para abrir la imagen en el Estudio", systemImage: "photo")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.region)
                        )
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: ReferenceImage.isSupported) else { return false }
                state.focus(url)
                return true
            } isTargeted: { isDropTarget = $0 }

            Rectangle().fill(Theme.border).frame(width: 1)
            ResultStrip()
                .frame(width: 128)
        }
        .onAppear {
            history.reload()
            syncTool()
        }
        .onChange(of: state.focusedURL) { syncTool() }
        .onChange(of: state.tool) { syncTool() }
        .onChange(of: preciseEdit.currentIndex) {
            // Navegar entre versiones en Editar también cambia la imagen seleccionada.
            if state.tool == .edit, let url = preciseEdit.current?.fileURL, url != state.focusedURL {
                state.focusedURL = url
            }
        }
        .confirmationDialog("¿Empezar de nuevo?", isPresented: $confirmReset) {
            Button("Empezar de nuevo", role: .destructive) {
                let original = preciseEdit.versions.first?.fileURL
                preciseEdit.reset()
                if let original { state.focusedURL = original; preciseEdit.load(original) }
            }
        } message: {
            Text("Se quitan las regiones y se vuelve a la imagen original. Los resultados siguen en la tira y en el Historial.")
        }
        .animation(.easeOut(duration: 0.18), value: showPrompt)
    }

    // MARK: Composición

    /// Generar, Borrar, Ampliar, Deblur, Probador y Vídeo: cabecera, escenario y barra.
    private var standardLayout: some View {
        VStack(spacing: 0) {
            FocusedHeader()
                .padding(.top, 30)
                .padding(.horizontal, 28)
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
            ToolSwitcher()
                .padding(.bottom, 10)
            bar
                .padding(.bottom, 20)
        }
    }

    /// Editar con precisión: lienzo a pantalla completa con barras flotantes.
    private var editLayout: some View {
        ZStack {
            if preciseEdit.current != nil {
                EditCanvas()
            } else {
                ToolLoadingView(isLoading: true, error: preciseEdit.loadError)
            }
            VStack(spacing: 0) {
                EditToolbar(confirmReset: $confirmReset)
                    .padding(.top, 18)
                Spacer()
                if showPrompt {
                    PromptPanel()
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ToolSwitcher()
                    .padding(.bottom, 10)
                PreciseEditBar(showPrompt: $showPrompt)
                    .padding(.bottom, 20)
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch state.tool {
        case .erase where state.focusedURL != nil:
            EraseStage(model: state.erase)
        case .outpaint where state.focusedURL != nil:
            OutpaintStage(model: state.outpaint)
        default:
            FocusedStage()
        }
    }

    @ViewBuilder
    private var bar: some View {
        switch state.tool {
        case .generate:
            PromptBarView()
        case .erase:
            if state.focusedURL != nil { EraseBar(model: state.erase) } else { NeedsImageBar() }
        case .outpaint:
            if state.focusedURL != nil { OutpaintBar(model: state.outpaint) } else { NeedsImageBar() }
        case .deblur:
            if state.focusedURL != nil { DeblurBar(model: state.deblur) } else { NeedsImageBar() }
        case .tryOn:
            if state.focusedURL != nil { TryOnBar(model: state.tryOn) } else { NeedsImageBar() }
        case .video:
            VideoComingBar()
        case .edit:
            NeedsImageBar()
        }
    }

    /// Carga la imagen seleccionada en la herramienta activa.
    private func syncTool() {
        let url = state.focusedURL
        switch state.tool {
        case .edit: preciseEdit.sync(with: url)
        case .erase: state.erase.sync(with: url)
        case .outpaint: state.outpaint.sync(with: url)
        case .deblur: state.deblur.sync(with: url)
        case .tryOn: state.tryOn.sync(with: url)
        case .generate, .video: break
        }
    }
}

// MARK: - Selector de herramientas

struct ToolSwitcher: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceTool.allCases) { tool in
                let disabled = tool.needsImage && state.focusedURL == nil
                Button { state.tool = tool } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tool.icon).font(.system(size: 12))
                        Text(tool.title).font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundStyle(state.tool == tool ? Color.white : Theme.textPrimary)
                    .background(Capsule().fill(state.tool == tool ? Theme.action : .clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.35 : 1)
                .help(disabled ? "Selecciona o genera una imagen primero" : tool.help)
            }
        }
        .padding(4)
        .surfaceStyle(cornerRadius: 20)
    }
}

private struct NeedsImageBar: View {
    var body: some View {
        ToolBarContainer {
            HStack {
                Image(systemName: "photo").foregroundStyle(Theme.textSecondary)
                Text("Elige una imagen de la tira de la derecha, arrastra una aquí o genera una nueva.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
    }
}

private struct VideoComingBar: View {
    var body: some View {
        ToolBarContainer {
            HStack {
                Image(systemName: "film").foregroundStyle(Theme.textSecondary)
                Text("Vídeo llega en la fase 5: texto a vídeo, imagen a vídeo con la imagen seleccionada, continuar, editar y escalar.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
    }
}

// MARK: - Cabecera de la imagen seleccionada

private struct FocusedHeader: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        HStack(spacing: 10) {
            if let url = state.focusedURL {
                let record = history.items.first { $0.fileURL == url }?.record
                VStack(alignment: .leading, spacing: 2) {
                    Text(record?.prompt ?? url.lastPathComponent)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(record?.prompt ?? url.path)
                    Text([record?.model, record.map { $0.createdAt.formatted(date: .abbreviated, time: .shortened) },
                          record?.cost.map { "\(formatCredits($0)) créditos" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 12)
                if let record {
                    Button { state.reuse(record) } label: { Chip(icon: "arrow.counterclockwise", text: "Reutilizar prompt") }
                        .buttonStyle(.plain)
                }
                Button { state.addReferences([url]) ; state.tool = .generate } label: {
                    Chip(icon: "square.on.square", text: "Usar como referencia")
                }
                .buttonStyle(.plain)
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Chip(icon: "folder", text: "Finder") }
                    .buttonStyle(.plain)
                Menu { ResultActions(fileURL: url, record: record) } label: { Chip(icon: "ellipsis", text: "Más") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            } else {
                Spacer()
            }
        }
        .frame(height: 36)
    }
}

// MARK: - Imagen seleccionada en grande

private struct FocusedStage: View {
    @EnvironmentObject private var state: AppState
    @State private var image: NSImage?
    @State private var parentImage: NSImage?
    @State private var compare = false
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        Group {
            if let url = state.focusedURL {
                if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
                    VideoPlayer(player: AVPlayer(url: url))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                } else if let image {
                    GeometryReader { geo in
                        let size = fittedSize(image.size, in: CGSize(width: geo.size.width, height: geo.size.height - 40))
                        VStack(spacing: 10) {
                            Group {
                                if compare, let parentImage {
                                    CompareView(before: parentImage, after: image, fraction: $fraction)
                                } else {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                                }
                            }
                            .frame(width: size.width, height: size.height)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
                            .contextMenu { ResultActions(fileURL: url) }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }

                            if parentImage != nil {
                                Button { compare.toggle() } label: {
                                    Chip(icon: "rectangle.split.2x1", text: "Antes / Después", isActive: compare)
                                }
                                .buttonStyle(.plain)
                                .help("Comparar con la imagen de la que sale este resultado")
                            } else {
                                Color.clear.frame(height: 28)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ProgressView()
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Describe una imagen abajo para empezar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("o arrastra aquí una imagen para editarla · ⌘↩ para generar")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: state.focusedURL) {
            image = nil
            parentImage = nil
            compare = false
            guard let url = state.focusedURL else { return }
            image = await ThumbnailLoader.load(url, maxPixelSize: 3000)
            if let parent = state.parent(of: url) {
                parentImage = await ThumbnailLoader.load(parent, maxPixelSize: 3000)
            }
        }
    }
}
