import SwiftUI

/// Placeholder animado mientras se genera.
struct ShimmerView: View {
    var cornerRadius: CGFloat = Theme.cornerResult
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.placeholder)
                .overlay(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: w * 0.6)
                    .offset(x: phase * w)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
