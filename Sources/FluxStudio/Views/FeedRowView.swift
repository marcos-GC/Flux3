import AppKit
import SwiftUI

/// Fila del feed: burbuja con el prompt + chip del modelo, y el grid de resultados.
struct FeedRowView: View {
    @EnvironmentObject private var state: AppState
    let item: FeedItem

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.prompt)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .lineLimit(12)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfaceStyle(cornerRadius: 16)

                if !item.referenceThumbnails.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(item.referenceThumbnails.enumerated()), id: \.offset) { _, thumb in
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }
                    .help("Imágenes de referencia usadas")
                }

                HStack(spacing: 6) {
                    Text(item.modelName)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.surface))
                        .overlay(Capsule().strokeBorder(Theme.border))
                        .foregroundStyle(Theme.textSecondary)
                    if item.totalCost > 0 {
                        Text("\(formatCredits(item.totalCost)) créditos")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if item.isRunning {
                        Button("Cancelar") { state.cancel(itemID: item.id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.danger)
                            .help("Deja de esperar el resultado. BFL puede cobrar igualmente si ya había empezado.")
                    } else {
                        Menu {
                            Button("Reutilizar prompt") { state.reuse(item) }
                            Button("Copiar prompt") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.prompt, forType: .string)
                            }
                            Divider()
                            Button("Quitar del feed") { state.remove(itemID: item.id) }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    }
                }
            }
            .frame(width: 280)

            ResultGrid(item: item)
            Spacer(minLength: 0)
        }
    }
}

private struct ResultGrid: View {
    let item: FeedItem

    private var cellSize: CGSize {
        let width: CGFloat = item.slots.count <= 1 ? 340 : (item.slots.count == 2 ? 280 : 210)
        var height = width / CGFloat(item.aspectRatio)
        height = min(height, 420)
        return CGSize(width: width, height: height)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(item.slots) { slot in
                ResultCell(slot: slot, size: cellSize, prompt: item.prompt)
            }
        }
    }
}

private struct ResultCell: View {
    let slot: ResultSlot
    let size: CGSize
    let prompt: String

    var body: some View {
        Group {
            switch slot.phase {
            case .done:
                if let image = slot.image, let url = slot.fileURL {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous))
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .contextMenu {
                            ResultActions(fileURL: url, prompt: prompt, expandedPrompt: slot.expandedPrompt)
                        }
                        .help(slot.expandedPrompt ?? "")
                } else {
                    message(icon: "photo", text: "Guardado, pero no se puede previsualizar")
                }
            case .failed(let text):
                message(icon: "exclamationmark.triangle", text: text)
            case .cancelled:
                message(icon: "xmark.circle", text: "Cancelado")
            default:
                ShimmerView()
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .bottomLeading) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(slot.statusText)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.85)))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(10)
                    }
            }
        }
    }

    private func message(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18))
            Text(text)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(14)
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerResult, style: .continuous)
                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}
