import AppKit
import FluxCore
import SwiftUI

/// Zona para elegir la imagen de entrada: botón, arrastrar y soltar, o Historial.
struct ToolDropZone: View {
    @EnvironmentObject private var history: HistoryStore
    let title: String
    var subtitle = "o arrastra una imagen aquí"
    var compact = false
    let onPick: (URL) -> Void
    @State private var isDropTarget = false
    @State private var showHistory = false

    var body: some View {
        VStack(spacing: compact ? 8 : 14) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: compact ? 22 : 32, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Button {
                if let url = chooseImages(allowsMultiple: false).first { onPick(url) }
            } label: {
                Text(title)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 16 : 24)
                    .padding(.vertical, compact ? 7 : 10)
                    .background(Capsule().fill(Theme.action))
            }
            .buttonStyle(.plain)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            Button("Usar una imagen del historial") { showHistory = true }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isDropTarget ? Theme.region.opacity(0.08) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isDropTarget ? Theme.region : Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: ReferenceImage.isSupported) else { return false }
            onPick(url)
            return true
        } isTargeted: { isDropTarget = $0 }
        .sheet(isPresented: $showHistory) {
            HistoryPicker { url in
                showHistory = false
                if let url { onPick(url) }
            }
            .environmentObject(history)
        }
    }
}

/// Cabecera de cada herramienta: título, descripción y acciones.
struct ToolHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            actions()
        }
        .padding(.horizontal, 32)
        .padding(.top, 34)
        .padding(.bottom, 12)
    }
}

/// Barra flotante inferior de las herramientas.
struct ToolBarContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(14)
            .frame(maxWidth: 900)
            .surfaceStyle(cornerRadius: Theme.cornerPromptBar)
            .padding(.horizontal, 28)
            .padding(.bottom, 22)
    }
}

/// Botón circular negro de generar, con estado y cancelación.
struct ToolGenerateControls: View {
    @ObservedObject var runner: ToolRunner
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if runner.isRunning {
                ProgressView().controlSize(.small)
                Text(runner.status).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                Button("Cancelar") { runner.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }
            Button(action: action) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.action.opacity(enabled && !runner.isRunning ? 1 : 0.3)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!enabled || runner.isRunning)
            .help("Generar (⌘↩)")
        }
    }
}

/// Chip "Ajustes" con tolerancia de seguridad, formato y (opcional) semilla.
struct ToolSettingsChip<Extra: View>: View {
    @ObservedObject var model: BaseToolModel
    var showsSeed = true
    @ViewBuilder var extra: () -> Extra
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Chip(icon: "slider.horizontal.3", text: "Ajustes", isActive: isOpen)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                SafetyToleranceControl(value: $model.safety, range: SafetyTolerance.range(for: model.endpoint))
                HStack {
                    SectionLabel("Formato de salida")
                    Spacer()
                    Picker("", selection: $model.format) {
                        ForEach(ToolOutputFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                }
                if showsSeed {
                    HStack {
                        SectionLabel("Semilla")
                        Spacer()
                        TextField("Aleatoria", text: $model.seedText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                    }
                    Text("Con la misma semilla y los mismos datos, el resultado se repite.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                extra()
            }
            .padding(16)
            .frame(width: 340)
        }
    }
}

extension ToolSettingsChip where Extra == EmptyView {
    init(model: BaseToolModel, showsSeed: Bool = true) {
        self.init(model: model, showsSeed: showsSeed, extra: { EmptyView() })
    }
}

/// Resultado actual (con comparador) + tira de resultados + acciones.
struct ToolResultView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var runner: ToolRunner
    let before: NSImage?
    var comparable = true
    let onUseAsInput: () -> Void
    @State private var showCompare = true
    @State private var fraction: CGFloat = 0.5

    var body: some View {
        if let result = runner.current {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    let size = fittedSize(result.image.size, in: geo.size)
                    Group {
                        if comparable && showCompare, let before {
                            CompareView(before: before, after: result.image, fraction: $fraction)
                        } else {
                            Image(nsImage: result.image).resizable()
                                .onDrag { NSItemProvider(contentsOf: result.url) ?? NSItemProvider() }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                    .contextMenu { ResultActions(fileURL: result.url) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack(spacing: 8) {
                    if comparable && before != nil {
                        Button { showCompare.toggle() } label: {
                            Chip(icon: "rectangle.split.2x1", text: "Antes / Después", isActive: showCompare)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { onUseAsInput() } label: {
                        Chip(icon: "arrow.uturn.left", text: "Seguir editando este resultado")
                    }
                    .buttonStyle(.plain)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([result.url]) } label: {
                        Chip(icon: "folder", text: "Mostrar en Finder")
                    }
                    .buttonStyle(.plain)
                    Menu {
                        ResultActions(fileURL: result.url)
                    } label: {
                        Chip(icon: "ellipsis", text: "Más")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    if runner.results.count > 1 {
                        Spacer()
                        ForEach(runner.results) { item in
                            Image(nsImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(item.id == result.id ? Theme.textPrimary : Theme.border, lineWidth: item.id == result.id ? 2 : 1)
                                )
                                .onTapGesture { runner.selectedID = item.id }
                        }
                    }
                }
            }
        }
    }
}

/// Tamaño de una imagen ajustada (sin recortar) a un espacio.
func fittedSize(_ image: CGSize, in container: CGSize) -> CGSize {
    guard image.width > 0, image.height > 0, container.width > 0, container.height > 0 else { return .zero }
    let scale = min(container.width / image.width, container.height / image.height)
    return CGSize(width: image.width * scale, height: image.height * scale)
}

/// Imagen de entrada mostrada grande y sin recortar.
struct FittedImage: View {
    let image: NSImage
    var size: CGSize? = nil

    var body: some View {
        GeometryReader { geo in
            let s = fittedSize(size ?? image.size, in: geo.size)
            Image(nsImage: image)
                .resizable()
                .frame(width: s.width, height: s.height)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
