import AppKit
import FluxCore
import SwiftUI

/// Tira vertical con todo lo generado (también en sesiones anteriores), lo más reciente arriba
/// y separado por días. Siempre visible, aunque se empiece de cero con «Nuevo».
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
                        ForEach(history.itemsByDay) { group in
                            DayHeader(day: group.day)
                            ForEach(group.items) { item in
                                StripThumb(item: item, selected: item.fileURL == state.focusedURL,
                                           isNew: state.isUnseen(item.fileURL))
                                    .id(item.id)
                                    .onTapGesture { state.focusedURL = item.fileURL }
                            }
                        }
                        if history.items.isEmpty && state.activeJobs.isEmpty && !state.isGenerating {
                            VStack(spacing: 6) {
                                Image(systemName: "square.stack")
                                    .font(.system(size: 18, weight: .light))
                                Text(history.isLoading ? "Cargando…" : "Aquí aparecerá todo lo que generes.")
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
                    if let id = history.items.first(where: { $0.fileURL == state.focusedURL })?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .background(Theme.surface)
    }
}

/// Separador de día en la tira: «Hoy», «Ayer» o la fecha.
private struct DayHeader: View {
    let day: Date

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Hoy" }
        if calendar.isDateInYesterday(day) { return "Ayer" }
        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())
    }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

private struct StripThumb: View {
    let item: StoredResult
    let selected: Bool
    var isNew = false
    @State private var thumbnail: NSImage?
    @State private var hovering = false

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
        .overlay(alignment: .bottomTrailing) {
            FavoriteButton(fileURL: item.fileURL, visibleWhenOff: hovering)
                .padding(4)
        }
        .overlay {
            if item.record.isFavorite {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.favorite, lineWidth: 2)
                    .padding(selected ? 2.5 : 0)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
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
        .onDrag { fileDragProvider(item.fileURL) }
        .task(id: item.fileURL) {
            thumbnail = await ThumbnailLoader.load(item.fileURL, maxPixelSize: 240)
        }
    }
}
