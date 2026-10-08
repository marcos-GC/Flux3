import AppKit
import FluxCore
import SwiftUI

/// Historial: grid de todo lo guardado, con búsqueda y filtro por modo.
struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var state: AppState
    @State private var search = ""
    @State private var model = HistoryView.allModels
    @State private var selected: StoredResult?

    static let allModels = "Todos los modos"

    private var filtered: [StoredResult] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return history.items.filter { item in
            (model == Self.allModels || item.record.model == model)
                && (query.isEmpty
                    || item.record.prompt.lowercased().contains(query)
                    || (item.record.expandedPrompt?.lowercased().contains(query) ?? false))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if history.items.isEmpty && !history.isLoading {
                empty(icon: "clock", title: "Todavía no hay nada guardado",
                      detail: "Los resultados aparecerán aquí. Se guardan en \(settings.outputFolder.path).")
            } else if filtered.isEmpty && !history.isLoading {
                empty(icon: "magnifyingglass", title: "Sin resultados", detail: "Prueba con otra búsqueda o filtro.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 16)], spacing: 18) {
                        ForEach(filtered) { item in
                            HistoryCell(item: item)
                                .onTapGesture { selected = item }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
        .onAppear { history.reload() }
        .sheet(item: $selected) { item in
            HistoryDetailView(item: item) { selected = nil }
                .environmentObject(state)
                .environmentObject(history)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Historial")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if history.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("\(filtered.count)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                TextField("Buscar en los prompts", text: $search)
                    .textFieldStyle(.plain)
                    .frame(width: 220)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .surfaceStyle(cornerRadius: 18)

            ChipPicker(
                icon: "line.3.horizontal.decrease",
                title: "Filtrar por modo",
                options: [Self.allModels] + history.models,
                selection: $model,
                label: { $0 }
            )

            Button { history.reload(force: true) } label: {
                Chip(icon: "arrow.clockwise", text: "Actualizar")
            }
            .buttonStyle(.plain)
            .help("Volver a leer la carpeta de salida")
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 18)
    }

    private func empty(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light))
            Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.system(size: 12)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: 420, maxHeight: .infinity)
    }
}

private struct HistoryCell: View {
    let item: StoredResult
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFill()
                    } else {
                        ShimmerView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous)
                        .strokeBorder(hovering ? Theme.textSecondary.opacity(0.5) : Theme.border)
                )
                .overlay(alignment: .topLeading) {
                    if item.isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                            .padding(8)
                    }
                }
                .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }

            Text(item.record.prompt)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
            Text("\(item.record.model) · \(item.record.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { ResultActions(fileURL: item.fileURL, record: item.record) }
        .task(id: item.fileURL) {
            thumbnail = await ThumbnailLoader.load(item.fileURL, maxPixelSize: 560)
        }
    }
}

/// Vista ampliada de un resultado, con su información y acciones.
private struct HistoryDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore
    let item: StoredResult
    let close: () -> Void
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Theme.background
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                        .padding(24)
                        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
                } else {
                    ProgressView()
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(Theme.border).frame(width: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SectionLabel("Prompt")
                    Text(item.record.prompt)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                    if let expanded = item.record.expandedPrompt, !expanded.isEmpty, expanded != item.record.prompt {
                        DisclosureGroup {
                            Text(expanded)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } label: {
                            SectionLabel("Prompt expandido por el modelo")
                        }
                    }

                    SectionLabel("Detalles").padding(.top, 6)
                    VStack(alignment: .leading, spacing: 5) {
                        info("Modelo", item.record.model)
                        info("Fecha", item.record.createdAt.formatted(date: .long, time: .shortened))
                        if let cost = item.record.cost { info("Coste", "\(formatCredits(cost)) créditos") }
                        if let ar = item.record.parameters["aspect_ratio"]?.stringValue { info("Proporción", ar) }
                        if let res = item.record.parameters["resolution"]?.stringValue { info("Resolución", res) }
                        if let st = item.record.parameters["safety_tolerance"]?.numberValue { info("Tolerancia", String(Int(st))) }
                        if let refs = item.record.referenceCount, refs > 0 { info("Referencias", String(refs)) }
                        info("Región", item.record.region.uppercased())
                        info("ID", item.record.taskID)
                        info("Archivo", item.fileURL.lastPathComponent)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button("Abrir en el Estudio") { close(); state.focus(item.fileURL) }
                            .keyboardShortcut(.defaultAction)
                        Button("Reutilizar prompt y parámetros") { close(); state.reuse(item.record) }
                        Button("Usar como referencia") { close(); state.useAsReference(item.fileURL) }
                        Menu("Enviar a…") {
                            Button("Editar con precisión") { close(); state.send(item.fileURL, to: .preciseEdit) }
                            Button("Outpainting") { close(); state.send(item.fileURL, to: .outpaint) }
                            Button("Borrar") { close(); state.send(item.fileURL, to: .erase) }
                            Button("Imagen a vídeo") { close(); state.send(item.fileURL, to: .video) }
                        }
                        .fixedSize()
                        HStack {
                            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.fileURL]) }
                            Button("Copiar") { copyImage(item.fileURL) }
                        }
                        Button("Mover a la Papelera", role: .destructive) {
                            history.moveToTrash(item)
                            close()
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 320)
            .background(Theme.surface)
        }
        .frame(minWidth: 900, minHeight: 600)
        .overlay(alignment: .topTrailing) {
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(12)
        }
        .task { image = NSImage(contentsOf: item.fileURL) }
        .preferredColorScheme(.light)
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
