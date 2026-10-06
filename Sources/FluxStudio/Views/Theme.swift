import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Paleta en modo claro.
enum Theme {
    static let background = Color(hex: 0xEDEDED)
    static let surface = Color(hex: 0xF7F7F7)
    static let border = Color(hex: 0xDADADA)
    static let textPrimary = Color(hex: 0x1A1A1A)
    static let textSecondary = Color(hex: 0x6B6B6B)
    static let action = Color(hex: 0x1A1A1A)
    static let region = Color(hex: 0x8B7CF6)
    static let placeholder = Color(hex: 0xE2E2E2)
    static let danger = Color(hex: 0xC2410C)

    static let cornerResult: CGFloat = 12
    static let cornerPromptBar: CGFloat = 28
}

/// Etiqueta pequeña en mayúsculas con tracking (estilo FLUX Tools).
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.textSecondary)
    }
}

extension View {
    /// Superficie clara con borde de 1 px y sombra muy suave.
    func surfaceStyle(cornerRadius: CGFloat) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}
