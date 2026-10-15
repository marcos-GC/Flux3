import AppKit
import FluxCore
import SwiftUI

/// Tira vertical de resultados de esta sesión (como el editor de Midjourney): lo más reciente arriba.
/// Lo de sesiones anteriores está en el Historial.
struct ResultStrip: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var history: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            Button {
                if let url = chooseImages(allowsMultiple: false).first { state.focus(url) }
            } label: {
                Label("Abrir", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .help("Abrir una imagen del Mac para trabajar con ella")
            .padding(.horizontal, 10)
            .padding(.top, 34)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.activeJobs) { job in
                            ShimmerView(cornerRadius: 8)
                                .frame(height: 96)
                                .overlay(alignment: .bottomLeading) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(job.label).font(.system(size: 9, weight: .semibold))
                                        Text(job.status).font(.system(size: 9))
                                    }
                                    .foregroundStyle(Theme.textPrimary)
                                    .padding(5)
                                }
                        }
                        if state.isGenerating && state.activeJobs.isEmpty {
                            ShimmerView(cornerRadius: 8).frame(height: 96)
                        }
                        ForEach(history.sessionItems) { item in
                            StripThumb(item: item, selected: item.fileURL == state.focusedURL,
                                       isNew: state.isUnseen(item.fileURL))
                                .id(item.id)
                                .onTapGesture { state.focusedURL = item.fileURL }
                        }
                        if history.sessionItems.isEmpty && state.activeJobs.isEmpty && !state.isGenerating {
                            VStack(spacing: 6) {
                                Image(systemName: "square.stack")
                                    .font(.system(size: 18, weight: .light))
                                Text("Aquí aparecerá lo que generes en esta sesión.")
                                Button("Ver el Historial") { state.mode = .history }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Theme.action)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .font(.system(size: 11))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
                .onChange(of: state.focusedURL) {
                    if let id = history.sessionItems.first(where: { $0.fileURL == state.focusedURL })?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .background(Theme.surface)
    }
}

private struct StripThumb: View {
    let item: StoredResult
    let selected: Bool
    var isNew = false
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Theme.placeholder)
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else if item.isVideo {
                Image(systemName: "film").foregroundStyle(Theme.textSecondary)
            }
            if item.isVideo {
                Image(systemName: item.record.draftCaches?.isEmpty == false ? "hare.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(4)
            }
            if isNew {
                Text("Nuevo")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.action))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(4)
                    .help("Resultado nuevo que aún no has abierto")
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(thumbnail.map { $0.size.width / max($0.size.height, 1) } ?? 1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Theme.textPrimary : Theme.border, lineWidth: selected ? 2.5 : 1)
        )
        .contentShape(Rectangle())
        .help("\(ToolNames.display(item.record.model)): \(item.record.prompt)")
        .contextMenu { ResultActions(fileURL: item.fileURL, record: item.record) }
        .onDrag { NSItemProvider(contentsOf: item.fileURL) ?? NSItemProvider() }
        .task(id: item.fileURL) {
            thumbnail = await ThumbnailLoader.load(item.fileURL, maxPixelSize: 240)
        }
    }
}
