import SwiftUI

/// Modo Generar: feed + barra de prompt flotante. Admite soltar imágenes como referencias.
struct GenerateView: View {
    @EnvironmentObject private var state: AppState
    @State private var isDropTarget = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FeedView()
            PromptBarView()
                .padding(.bottom, 22)
        }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.region, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(Theme.region.opacity(0.06))
                    .overlay(
                        Label("Suelta para añadir como referencia", systemImage: "square.on.square")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.region)
                    )
                    .padding(16)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            state.addReferences(urls)
            return true
        } isTargeted: { isDropTarget = $0 }
    }
}
