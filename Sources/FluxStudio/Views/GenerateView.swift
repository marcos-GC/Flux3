import SwiftUI

/// Modo Generar: feed + barra de prompt flotante.
struct GenerateView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack(alignment: .bottom) {
            FeedView()
            PromptBarView()
                .padding(.bottom, 22)
        }
    }
}
