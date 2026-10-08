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
    @State private var compare = false
    @State private var focusedSize: CGSize?

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
            updateFocusedSize()
        }
        .onChange(of: state.focusedURL) {
            compare = false
            syncTool()
            updateFocusedSize()
        }
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

    /// Imagen centrada en el espacio libre (con su línea de información debajo)
    /// y la caja del prompt FIJA en la parte inferior de la ventana.
    private var standardLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let infoHeight: CGFloat = state.focusedURL == nil ? 0 : 34
                let available = CGSize(
                    width: max(200, geo.size.width - 64),
                    height: max(120, geo.size.height - infoHeight - 40)
                )
                let stageSize = contentSize.map { fittedSize($0, in: available) }
                    ?? CGSize(width: available.width, height: min(available.height, 320))

                VStack(spacing: 8) {
                    stage
                        .frame(width: stageSize.width, height: stageSize.height)
                    if state.focusedURL != nil {
                        ImageInfoRow(compare: $compare, showsCompare: showsCompare)
                            .frame(width: max(stageSize.width, min(available.width, 640)))
                            .frame(height: infoHeight)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(.top, 24)
            .padding(.bottom, 12)

            bar
                .padding(.bottom, 20)
        }
    }

    /// Editar con precisión: lienzo con zoom; barra de regiones y caja del prompt debajo.
    private var editLayout: some View {
        ZStack {
            if preciseEdit.current != nil {
                EditCanvas()
            } else {
                ToolLoadingView(isLoading: true, error: preciseEdit.loadError)
            }
            VStack(spacing: 8) {
                Spacer()
                if showPrompt {
                    PromptPanel()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                EditToolbar(confirmReset: $confirmReset)
                PreciseEditBar(showPrompt: $showPrompt)
                    .padding(.bottom, 20)
            }
        }
    }

    /// Tamaño (proporción) de lo que se muestra en el escenario.
    private var contentSize: CGSize? {
        guard state.focusedURL != nil else { return nil }
        switch state.tool {
        case .erase: return state.erase.input?.size ?? focusedSize
        case .outpaint:
            guard state.outpaint.input != nil else { return focusedSize }
            // Deja sitio al texto con el tamaño del lienzo.
            return CGSize(width: state.outpaint.canvasSize.width, height: state.outpaint.canvasSize.height * 1.08)
        default: return focusedSize
        }
    }

    private var showsCompare: Bool {
        state.tool != .erase && state.tool != .outpaint && state.parent(of: state.focusedURL) != nil
    }

    private func updateFocusedSize() {
        guard let url = state.focusedURL else { focusedSize = nil; return }
        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            focusedSize = CGSize(width: 16, height: 9)
        } else if let px = ImageEncoder.pixelSize(fileURL: url) {
            focusedSize = CGSize(width: px.width, height: px.height)
        } else {
            focusedSize = nil
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
            FocusedStage(compare: compare)
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

// MARK: - Línea de información bajo la imagen

private struct ImageInfoRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    @Binding var compare: Bool
    let showsCompare: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let url = state.focusedURL {
                let record = history.items.first { $0.fileURL == url }?.record
                VStack(alignment: .leading, spacing: 1) {
                    Text(record?.prompt ?? url.lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(record?.prompt ?? url.path)
                    Text([record?.model, record?.cost.map { "\(formatCredits($0)) créditos" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 10)
                if showsCompare {
                    Button { compare.toggle() } label: {
                        Chip(icon: "rectangle.split.2x1", text: "Antes / Después", isActive: compare)
                    }
                    .buttonStyle(.plain)
                    .help("Comparar con la imagen de la que sale este resultado")
                }
                if let record {
                    Button { state.reuse(record) } label: { Chip(icon: "arrow.counterclockwise", text: "Reutilizar") }
                        .buttonStyle(.plain)
                        .help("Volver a poner este prompt y sus parámetros en Generar")
                }
                Button { state.addReferences([url]); state.tool = .generate } label: {
                    Chip(icon: "square.on.square", text: "Referencia")
                }
                .buttonStyle(.plain)
                .help("Usar esta imagen como referencia para generar")
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Chip(icon: "folder", text: "Finder") }
                    .buttonStyle(.plain)
                Menu { ResultActions(fileURL: url, record: record) } label: { Chip(icon: "ellipsis", text: "Más") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Imagen seleccionada en grande

private struct FocusedStage: View {
    @EnvironmentObject private var state: AppState
    let compare: Bool
    @State private var image: NSImage?
    @State private var parentImage: NSImage?
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        Group {
            if let url = state.focusedURL {
                if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
                    VideoPlayer(player: AVPlayer(url: url))
                } else if let image {
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
                    .contextMenu { ResultActions(fileURL: url) }
                    .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                } else {
                    ShimmerView()
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
        .shadow(color: .black.opacity(state.focusedURL == nil ? 0 : 0.08), radius: 14, y: 4)
        .task(id: state.focusedURL) {
            image = nil
            parentImage = nil
            guard let url = state.focusedURL else { return }
            image = await ThumbnailLoader.load(url, maxPixelSize: 3000)
            if let parent = state.parent(of: url) {
                parentImage = await ThumbnailLoader.load(parent, maxPixelSize: 3000)
            }
        }
    }
}
