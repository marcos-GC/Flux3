import SwiftUI

/// Área central tipo feed: una fila por petición, la más reciente abajo.
struct FeedView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.feed.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                Text("Describe una imagen abajo para empezar")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("⌘↩ para generar")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 160)
        } else {
            GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        ForEach(state.feed) { item in
                            FeedRowView(item: item).id(item.id)
                        }
                    }
                    .padding(.horizontal, 36)
                    .padding(.top, 44)
                    .padding(.bottom, 220) // espacio para la barra flotante
                }
                .onAppear { scrollToLast(proxy) }
                .onChange(of: state.feed.count) { scrollToLast(proxy) }
            }
            // Ancho del grid = ventana − márgenes (36+36) − columna del prompt (280) − separación (24).
            .environment(\.feedSpace, FeedSpace(
                gridWidth: max(200, geo.size.width - 72 - 280 - 24),
                maxHeight: max(260, geo.size.height - 300)
            ))
            }
        }
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard let last = state.feed.last?.id else { return }
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
    }
}
