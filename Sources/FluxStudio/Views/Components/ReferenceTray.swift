import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Fila de miniaturas numeradas ("Image 1", "Image 2"…) dentro de la barra de prompt.
struct ReferenceTray: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(state.references.enumerated()), id: \.element.id) { index, reference in
                        ReferenceThumb(
                            reference: reference,
                            index: index,
                            isFirst: index == 0,
                            isLast: index == state.references.count - 1
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            HStack(spacing: 4) {
                Image(systemName: "info.circle").font(.system(size: 10))
                Text("Cítalas en el prompt como «Image 1», «Image 2»… Con proporción Auto, la primera fija el formato.")
                    .font(.system(size: 11))
                Spacer()
                Button("Quitar todas") { state.clearReferences() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct ReferenceThumb: View {
    @EnvironmentObject private var state: AppState
    let reference: ReferenceImage
    let index: Int
    let isFirst: Bool
    let isLast: Bool
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.placeholder)
            if let thumb = reference.thumbnail {
                Image(nsImage: thumb).resizable().scaledToFill()
            }
            if reference.isProcessing {
                ProgressView().controlSize(.small)
            } else if reference.error != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                    .padding(6)
                    .background(Circle().fill(.white))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
        .overlay(alignment: .bottomLeading) {
            Text("Image \(index + 1)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.65)))
                .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { state.removeReference(reference.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(3)
                .help("Quitar")
            }
        }
        .overlay(alignment: .center) {
            if hovering && !reference.isProcessing {
                HStack {
                    arrow("chevron.left", disabled: isFirst) { state.moveReference(reference.id, by: -1) }
                    Spacer()
                    arrow("chevron.right", disabled: isLast) { state.moveReference(reference.id, by: 1) }
                }
                .padding(.horizontal, 2)
            }
        }
        .onHover { hovering = $0 }
        .help(reference.error ?? reference.sourceURL.lastPathComponent)
        .contextMenu {
            Button("Mover a la izquierda") { state.moveReference(reference.id, by: -1) }.disabled(isFirst)
            Button("Mover a la derecha") { state.moveReference(reference.id, by: 1) }.disabled(isLast)
            Button("Mostrar en Finder") { NSWorkspace.shared.activateFileViewerSelecting([reference.sourceURL]) }
            Divider()
            Button("Quitar") { state.removeReference(reference.id) }
        }
    }

    private func arrow(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0 : 1)
        .disabled(disabled)
    }
}

/// Selector de archivos para añadir referencias.
@MainActor
func chooseImages(allowsMultiple: Bool = true) -> [URL] {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = allowsMultiple
    panel.canChooseDirectories = false
    panel.prompt = "Añadir"
    return panel.runModal() == .OK ? panel.urls : []
}
