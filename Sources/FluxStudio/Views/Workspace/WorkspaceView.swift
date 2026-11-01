import AppKit
import AVKit
import FluxCore
import SwiftUI
import UniformTypeIdentifiers

/// Pantalla principal (Estudio): imagen seleccionada en grande, herramientas abajo
/// y tira de resultados a la derecha. Todo se hace sobre la imagen seleccionada.
struct WorkspaceView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var preciseEdit: PreciseEditModel
    @State private var showPrompt = false
    @State private var confirmReset = false
    @State private var dropZone: StudioDropZone?
    @State private var compare = false
    @State private var focusedSize: CGSize?
    @State private var studioWidth: CGFloat = 900
    /// Zoom y recorte de la imagen en grande (y el recorte de Editar).
    @StateObject private var viewer = ViewerZoom()

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                if state.tool == .collage && state.compareURL == nil {
                    CollageWorkspace(model: state.collage)
                } else if state.tool == .edit && state.focusedURL != nil && state.compareURL == nil {
                    editLayout
                } else {
                    standardLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Resultado que ha llegado mientras trabajabas en otra imagen.
            .overlay(alignment: .top) {
                if let notice = state.readyNotice {
                    ReadyToast(notice: notice)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: state.readyNotice)
            // Al arrastrar imágenes desde el Finder: zona izquierda = editar, derecha = referencia.
            .overlay {
                if let dropZone, state.tool != .collage {
                    StudioDropOverlay(active: dropZone)
                        .allowsHitTesting(false)
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(key: StudioWidthKey.self, value: geo.size.width)
            })
            .onPreferenceChange(StudioWidthKey.self) { studioWidth = $0 }
            .onDrop(of: [.fileURL], delegate: StudioDropDelegate(zone: $dropZone, width: studioWidth) { urls, zone in
                handleDrop(urls, zone: zone)
            })

            AssistantColumn(store: state.assistant)
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
            viewer.reset()
            syncTool()
            updateFocusedSize()
        }
        .onChange(of: state.tool) {
            viewer.reset()
            syncTool()
        }
        .onChange(of: compare) { viewer.cancelCrop() }
        .onChange(of: state.compareURL) { viewer.cancelCrop() }
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
            // Zoom y recorte, en horizontal arriba a la derecha.
            HStack {
                Spacer()
                if showsViewerControls {
                    StageViewerControls(viewer: viewer, imageAspect: focusedAspect,
                                        canCrop: state.compareURL == nil && !compare)
                }
            }
            .frame(height: 36)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            GeometryReader { geo in
                let infoHeight: CGFloat = state.focusedURL == nil ? 0 : 32
                let available = CGSize(
                    width: max(200, geo.size.width - 64),
                    height: max(120, geo.size.height - infoHeight - 16)
                )
                let stageSize = contentSize.map { fittedSize($0, in: available) }
                    ?? CGSize(width: available.width, height: min(available.height, 320))

                VStack(spacing: 6) {
                    stage
                        .frame(width: stageSize.width, height: stageSize.height)
                    if state.focusedURL != nil {
                        ImageCaption()
                            .frame(width: max(stageSize.width, min(available.width, 640)))
                            .frame(height: infoHeight)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                if state.focusedURL != nil {
                    StudioToolbar(compare: $compare, showsCompare: showsCompare, canCompare: canCompare,
                                  maxWidth: state.tool == .generate ? 820 : 900)
                }
                bar
            }
            .padding(.bottom, 20)
        }
    }

    /// Editar con precisión: lienzo con zoom; barra de regiones y caja del prompt debajo.
    private var editLayout: some View {
        ZStack {
            if preciseEdit.current != nil {
                EditCanvas(viewer: viewer)
            } else {
                ToolLoadingView(isLoading: true, error: preciseEdit.loadError)
            }
            VStack(spacing: 8) {
                Spacer()
                if showPrompt {
                    PromptPanel()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                EditToolbar(viewer: viewer, confirmReset: $confirmReset)
                PreciseEditBar(showPrompt: $showPrompt)
                    .padding(.bottom, 20)
            }
        }
    }

    /// Tamaño (proporción) de lo que se muestra en el escenario.
    private var contentSize: CGSize? {
        guard state.focusedURL != nil else { return nil }
        if compare || state.compareURL != nil { return focusedSize }
        switch state.tool {
        case .erase: return state.erase.input?.size ?? focusedSize
        case .fill: return state.fill.input?.size ?? focusedSize
        case .outpaint:
            guard state.outpaint.input != nil else { return focusedSize }
            // Deja sitio al texto con el tamaño del lienzo.
            return CGSize(width: state.outpaint.canvasSize.width, height: state.outpaint.canvasSize.height * 1.08)
        default: return focusedSize
        }
    }

    /// «Antes / Después» está siempre que se ve una imagen (no un vídeo)…
    private var showsCompare: Bool {
        guard state.compareURL == nil, let url = state.focusedURL else { return false }
        return !VideoModel.isVideo(url)
    }

    /// …y se puede usar cuando la imagen sale de otra.
    private var canCompare: Bool {
        showsCompare && state.parent(of: state.focusedURL) != nil
    }

    /// Zoom y recorte a la derecha de la imagen (en todas las herramientas, también en los
    /// lienzos de Borrar, Rellenar y Ampliar).
    private var showsViewerControls: Bool {
        guard let url = state.focusedURL else { return false }
        return !VideoModel.isVideo(url)
    }

    private var focusedAspect: CGFloat {
        guard let size = focusedSize, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func updateFocusedSize() {
        guard let url = state.focusedURL else { focusedSize = nil; return }
        if VideoModel.isVideo(url) {
            focusedSize = CGSize(width: 16, height: 9)
            Task {
                if let info = await VideoInfo.load(url), info.size.width > 0, state.focusedURL == url {
                    focusedSize = info.size
                }
            }
        } else if let px = ImageEncoder.pixelSize(fileURL: url) {
            focusedSize = CGSize(width: px.width, height: px.height)
        } else {
            focusedSize = nil
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch state.compareURL != nil || compare ? WorkspaceTool.generate : state.tool {
        case .erase where state.focusedURL != nil:
            MaskStage(model: state.erase, viewer: viewer)
        case .fill where state.focusedURL != nil:
            MaskStage(model: state.fill, viewer: viewer)
        case .outpaint where state.focusedURL != nil:
            OutpaintStage(model: state.outpaint, viewer: viewer)
        default:
            FocusedStage(compare: compare, viewer: viewer)
        }
    }

    @ViewBuilder
    private var bar: some View {
        switch state.tool {
        case .generate:
            PromptBarView()
        case .erase:
            if state.focusedURL != nil { EraseBar(model: state.erase) } else { NeedsImageBar() }
        case .fill:
            if state.focusedURL != nil { FillBar(model: state.fill) } else { NeedsImageBar() }
        case .outpaint:
            if state.focusedURL != nil { OutpaintBar(model: state.outpaint) } else { NeedsImageBar() }
        case .deblur:
            if state.focusedURL != nil { DeblurBar(model: state.deblur) } else { NeedsImageBar() }
        case .tryOn:
            if state.focusedURL != nil { TryOnBar(model: state.tryOn) } else { NeedsImageBar() }
        case .video:
            VideoBar(model: state.video)
        case .edit:
            if state.compareURL != nil { CompareHintBar() } else { NeedsImageBar() }
        case .collage:
            CompareHintBar()
        }
    }

    /// Imágenes soltadas desde el Finder.
    private func handleDrop(_ urls: [URL], zone: StudioDropZone) {
        // En el collage, lo que se suelta se añade como objeto (o como base si aún no hay).
        if state.tool == .collage && state.compareURL == nil {
            let images = urls.filter(ReferenceImage.isSupported)
            if images.isEmpty {
                state.alert = AppAlert(title: "Archivo no compatible", message: "Solo se pueden usar imágenes (JPEG, PNG, WebP, HEIC…).")
            } else {
                state.collage.add(images)
            }
            return
        }
        state.receive(urls, as: zone)
    }

    /// Carga la imagen seleccionada en la herramienta activa.
    private func syncTool() {
        let url = state.focusedURL
        switch state.tool {
        case .edit: preciseEdit.sync(with: url, parent: state.parent(of: url))
        case .erase: state.erase.sync(with: url)
        case .fill: state.fill.sync(with: url)
        case .outpaint: state.outpaint.sync(with: url)
        case .deblur: state.deblur.sync(with: url)
        case .tryOn: state.tryOn.sync(with: url)
        case .generate, .video, .collage: break
        }
    }
}

/// Panel del Asistente de prompts, entre la imagen y la tira (si está abierto).
private struct AssistantColumn: View {
    @ObservedObject var store: AssistantStore

    var body: some View {
        if store.isOpen {
            Rectangle().fill(Theme.border).frame(width: 1)
            AssistantPanel(store: store)
                .frame(width: 380)
                .transition(.move(edge: .trailing))
        }
    }
}

/// Aviso discreto «Listo · Ver», sin interrumpir lo que estás haciendo.
private struct ReadyToast: View {
    @EnvironmentObject private var state: AppState
    let notice: ReadyNotice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.anchorColor)
            Text("Listo: \(ToolNames.display(notice.label))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Button("Ver") {
                if state.tool == .collage { state.selectTool(.generate) }
                state.focusedURL = notice.url
            }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .underline()
            Button { state.readyNotice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .help("Cerrar aviso")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .surfaceStyle(cornerRadius: 18)
        .task(id: notice.id) {
            try? await Task.sleep(for: .seconds(6))
            if state.readyNotice?.id == notice.id { state.readyNotice = nil }
        }
    }
}

/// En Editar, mientras se comparan dos fotos de la galería.
private struct CompareHintBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ToolBarContainer {
            HStack {
                Image(systemName: "rectangle.split.2x1").foregroundStyle(Theme.textSecondary)
                Text("Comparando dos imágenes. Termina la comparación (Esc) para seguir editando.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Terminar comparación") { state.compareURL = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
            }
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

// MARK: - Línea de información bajo la imagen

/// Prompt y modelo de la imagen en grande (las acciones están en la barra de iconos).
private struct ImageCaption: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        if let url = state.focusedURL {
            let record = history.items.first { $0.fileURL == url }?.record
            VStack(spacing: 1) {
                Text(record?.prompt ?? url.lastPathComponent)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(record?.prompt ?? url.path)
                Text([record.map { ToolNames.display($0.model) }, record?.cost.map { "\(formatCredits($0)) créditos" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Barra de iconos encima de la caja (igual que en Editar)

private struct StudioToolbar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    @Binding var compare: Bool
    let showsCompare: Bool
    let canCompare: Bool
    let maxWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if let url = state.focusedURL {
                let record = history.items.first { $0.fileURL == url }?.record
                let isVideo = VideoModel.isVideo(url)
                if state.compareURL != nil {
                    ToolIconButton(icon: "arrow.left.arrow.right", help: "Intercambiar: cambiar de lado las dos imágenes") {
                        state.swapCompare()
                    }
                    ToolIconButton(icon: "xmark.rectangle", help: "Terminar la comparación de las dos imágenes (Esc)", isActive: true) {
                        state.compareURL = nil
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    divider
                }
                if state.original(of: url) != nil {
                    ToolIconButton(icon: "arrow.uturn.backward",
                                   help: "Original: volver a la imagen antes de editarla (⌘↑). Las ediciones siguen en la tira.") {
                        state.goToOriginal()
                    }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                }
                if showsCompare {
                    ToolIconButton(icon: "rectangle.split.2x1",
                                   help: canCompare
                                       ? "Antes / Después: comparar con la imagen de la que sale este resultado"
                                       : "Antes / Después: esta imagen no sale de otra. Para comparar dos fotos cualesquiera, ⌘-clic en una miniatura de la tira.",
                                   isActive: compare) {
                        compare.toggle()
                    }
                    .disabled(!canCompare)
                }
                if state.original(of: url) != nil || showsCompare || state.compareURL != nil {
                    divider
                }
                if isVideo {
                    ForEach([VideoModel.Mode.v2v, .edit, .upscale]) { mode in
                        ToolIconButton(icon: mode.icon, help: mode.title) {
                            state.video.mode = mode
                            state.tool = .video
                        }
                    }
                } else {
                    if let record {
                        ToolIconButton(icon: "arrow.counterclockwise",
                                       help: "Reutilizar: volver a poner este prompt y sus parámetros en Generar") {
                            state.reuse(record)
                        }
                    }
                    ToolIconButton(icon: "square.on.square", help: "Como referencia: usar esta imagen como referencia para generar") {
                        state.useAsReference(url)
                    }
                    ToolIconButton(icon: "film", help: "A vídeo: imagen a vídeo con esta imagen como fotograma inicial") {
                        state.send(url, to: .video)
                    }
                    ToolIconButton(icon: "bubble.left.and.text.bubble.right", help: "Enviar al asistente de prompts") {
                        state.assistant.attach([url])
                    }
                }
                divider
                ToolIconButton(icon: "folder", help: "Mostrar en el Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Menu { ResultActions(fileURL: url, record: record) } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 30, height: 28)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Más acciones")
                Spacer(minLength: 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .surfaceStyle(cornerRadius: 14)
        // Mismo ancho que la caja de abajo.
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, 28)
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 18).padding(.horizontal, 4)
    }
}

// MARK: - Imagen seleccionada en grande

private struct FocusedStage: View {
    @EnvironmentObject private var state: AppState
    let compare: Bool
    @ObservedObject var viewer: ViewerZoom
    @State private var panStart: CGSize?
    @State private var image: NSImage?
    @State private var parentImage: NSImage?
    @State private var otherImage: NSImage?
    @State private var player: AVPlayer?
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        Group {
            if let url = state.focusedURL {
                if VideoModel.isVideo(url) {
                    if let player {
                        VideoPlayer(player: player)
                            .contextMenu { ResultActions(fileURL: url) }
                    } else {
                        ShimmerView()
                    }
                } else if let image {
                    GeometryReader { geo in
                        let comparing = state.compareURL != nil || compare
                        ZStack(alignment: .topLeading) {
                            Group {
                                if state.compareURL != nil, let otherImage {
                                    // Dos fotos de la galería: la elegida para comparar a la izquierda.
                                    CompareView(before: otherImage, after: image, fraction: $fraction,
                                                beforeLabel: "IMAGEN 1", afterLabel: "IMAGEN 2")
                                } else if compare, let parentImage {
                                    CompareView(before: parentImage, after: image, fraction: $fraction)
                                } else if viewer.zoom > 1 || viewer.isCropping {
                                    // Con zoom, arrastrar desplaza la imagen (en vez de sacarla al Finder).
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                } else {
                                    Image(nsImage: image)
                                        .resizable()
                                        .interpolation(.high)
                                        .onDrag { fileDragProvider(url) }
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(viewer.zoom)
                            .offset(viewer.pan)

                            if viewer.isCropping && !comparing {
                                CropOverlay(viewer: viewer, frame: viewer.imageFrame(in: geo.size), space: "stage",
                                            imageAspect: geo.size.height > 0 ? geo.size.width / geo.size.height : 1)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        .coordinateSpace(name: "stage")
                        .contentShape(Rectangle())
                        .gesture(panGesture, including: viewer.zoom > 1 && !viewer.isCropping && !comparing ? .all : .subviews)
                    }
                    .zoomEvents(viewer)
                    .contextMenu { ResultActions(fileURL: url) }
                    .onTapGesture(count: 2) {
                        if !viewer.isCropping { NSWorkspace.shared.open(url) }
                    }
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
            player?.pause()
            player = nil
            guard let url = state.focusedURL else { return }
            if VideoModel.isVideo(url) {
                player = AVPlayer(url: url)
                return
            }
            // Primero una versión ligera (aparece al instante al recorrer la tira) y luego la
            // de alta resolución, para que se vea nítida en pantallas Retina grandes.
            image = await ThumbnailLoader.load(url, maxPixelSize: 1024)
            guard !Task.isCancelled else { return }
            if let full = await ThumbnailLoader.load(url, maxPixelSize: 3000), !Task.isCancelled {
                image = full
            }
        }
        .task(id: state.compareURL) {
            otherImage = nil
            guard let other = state.compareURL else { return }
            otherImage = await ThumbnailLoader.load(other, maxPixelSize: 3000)
        }
        // La imagen de «Antes» solo se carga al comparar.
        .task(id: compare) {
            guard compare, parentImage == nil, let url = state.focusedURL,
                  let parent = state.parent(of: url) else { return }
            parentImage = await ThumbnailLoader.load(parent, maxPixelSize: 3000)
        }
    }
}

extension FocusedStage {
    /// Con zoom: arrastrar desplaza la imagen.
    fileprivate var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if panStart == nil { panStart = viewer.pan }
                guard let start = panStart else { return }
                viewer.pan = CGSize(width: start.width + value.translation.width,
                                    height: start.height + value.translation.height)
            }
            .onEnded { _ in panStart = nil }
    }
}

/// Zoom y recorte de la imagen en grande, en horizontal arriba a la derecha.
private struct StageViewerControls: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var viewer: ViewerZoom
    let imageAspect: CGFloat
    let canCrop: Bool

    var body: some View {
        HStack(spacing: 0) {
            if viewer.isCropping, let url = state.focusedURL {
                CropActionButtons(viewer: viewer, imageAspect: imageAspect) {
                    guard let rect = viewer.cropRect else { return }
                    viewer.cancelCrop()
                    state.saveCrop(of: url, rect: rect)
                }
            } else {
                ZoomButtons(zoom: $viewer.zoom, pan: $viewer.pan, minZoom: viewer.minZoom,
                            maxZoom: viewer.maxZoom)
                Rectangle().fill(Theme.border).frame(width: 1, height: 18).padding(.horizontal, 4)
                ToolIconButton(icon: "crop", help: canCrop
                    ? "Recortar: el recorte se guarda como imagen nueva en la tira; la original no cambia"
                    : "Termina la comparación para recortar") {
                    viewer.startCrop()
                }
                .disabled(!canCrop)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .surfaceStyle(cornerRadius: 12)
    }
}

// MARK: - Soltar imágenes desde el Finder

enum StudioDropZone {
    case edit, reference
}

private struct StudioWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 900
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Decide la zona según dónde está el puntero (izquierda 60 % = editar, derecha = referencia).
private struct StudioDropDelegate: DropDelegate {
    @Binding var zone: StudioDropZone?
    let width: CGFloat
    let onDrop: ([URL], StudioDropZone) -> Void

    static let editFraction: CGFloat = 0.6

    private func zoneAt(_ info: DropInfo) -> StudioDropZone {
        info.location.x < width * Self.editFraction ? .edit : .reference
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        zone = zoneAt(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let current = zoneAt(info)
        if zone != current { zone = current }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        zone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let target = zoneAt(info)
        zone = nil
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.loadURL(provider) { urls.append(url) }
            }
            onDrop(urls, target)
        }
        return true
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        if provider.canLoadObject(ofClass: URL.self) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url { return url }
        }
        // Algunas apps dan la URL como datos sin envolver.
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url)
                case let data as Data: continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// Las dos zonas que aparecen al arrastrar una imagen.
private struct StudioDropOverlay: View {
    let active: StudioDropZone

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                zoneView(.edit, icon: "pencil.and.outline", title: "Editar esta imagen",
                         detail: "Se abre en grande, lista para editar: escribe el cambio o dibuja regiones.")
                    .frame(width: (geo.size.width - 44) * StudioDropDelegate.editFraction)
                zoneView(.reference, icon: "square.on.square", title: "Usar como referencia",
                         detail: "Se añade a la caja del prompt como «image 1, 2…» para generar algo nuevo.")
            }
            .padding(16)
        }
        .background(Theme.background.opacity(0.55))
        .animation(.easeOut(duration: 0.12), value: active)
    }

    private func zoneView(_ zone: StudioDropZone, icon: String, title: String, detail: String) -> some View {
        let isActive = zone == active
        return VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
            Text(title.uppercased())
                .font(.system(size: 14, weight: .semibold))
                .tracking(1)
            Text(detail)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .foregroundStyle(isActive ? Theme.region : Theme.textSecondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isActive ? Theme.region.opacity(0.14) : Theme.surface.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isActive ? Theme.region : Theme.border,
                              style: StrokeStyle(lineWidth: isActive ? 2.5 : 1.5, dash: [8, 6]))
        )
        .scaleEffect(isActive ? 1 : 0.98)
    }
}
