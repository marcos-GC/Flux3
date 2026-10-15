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
                if let dropZone {
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
            VideoBar(model: state.video)
        case .edit:
            NeedsImageBar()
        }
    }

    /// Imágenes soltadas desde el Finder.
    private func handleDrop(_ urls: [URL], zone: StudioDropZone) {
        let images = urls.filter(ReferenceImage.isSupported)
        guard !images.isEmpty else {
            state.alert = AppAlert(title: "Archivo no compatible", message: "Solo se pueden soltar imágenes (JPEG, PNG, WebP, HEIC…).")
            return
        }
        switch zone {
        case .edit:
            // Se abre directamente en Editar: escribir el cambio o dibujar regiones.
            state.focus(images[0], tool: .edit)
        case .reference:
            state.addReferences(images)
            state.selectTool(.generate)
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
            Button("Ver") { state.focusedURL = notice.url }
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
                    Text([record.map { ToolNames.display($0.model) }, record?.cost.map { "\(formatCredits($0)) créditos" }]
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
                if VideoModel.isVideo(url) {
                    ForEach([VideoModel.Mode.v2v, .edit, .upscale]) { mode in
                        Button {
                            state.video.mode = mode
                            state.tool = .video
                        } label: {
                            Chip(icon: mode.icon, text: mode == .v2v ? "Continuar" : (mode == .edit ? "Editar" : "Escalar"))
                        }
                        .buttonStyle(.plain)
                        .help(mode.title)
                    }
                } else if let record {
                    Button { state.reuse(record) } label: { Chip(icon: "arrow.counterclockwise", text: "Reutilizar") }
                        .buttonStyle(.plain)
                        .help("Volver a poner este prompt y sus parámetros en Generar")
                }
                if !VideoModel.isVideo(url) {
                    Button { state.useAsReference(url) } label: {
                        Chip(icon: "square.on.square", text: "Como referencia")
                    }
                    .buttonStyle(.plain)
                    .help("Usar esta imagen como referencia para generar")
                    Button { state.send(url, to: .video) } label: { Chip(icon: "film", text: "A vídeo") }
                        .buttonStyle(.plain)
                        .help("Imagen a vídeo con esta imagen como fotograma inicial")
                }
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
        // La imagen de «Antes» solo se carga al comparar.
        .task(id: compare) {
            guard compare, parentImage == nil, let url = state.focusedURL,
                  let parent = state.parent(of: url) else { return }
            parentImage = await ThumbnailLoader.load(parent, maxPixelSize: 3000)
        }
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
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
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
