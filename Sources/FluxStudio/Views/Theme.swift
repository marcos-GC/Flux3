import FluxCore
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

    /// Un color por región, como en la herramienta oficial (1 violeta, 2 azul…).
    static let regionPalette: [Color] = [
        Color(hex: 0x8B7CF6), Color(hex: 0x4F8EF7), Color(hex: 0x22A699), Color(hex: 0xE0962F),
        Color(hex: 0xE0559A), Color(hex: 0x6B7FD7), Color(hex: 0xB0703A), Color(hex: 0x7A9B2F),
    ]
    static let anchorColor = Color(hex: 0x3F9D6B)

    static func regionColor(_ index: Int, kind: RegionKind = .edit) -> Color {
        kind == .anchor ? anchorColor : regionPalette[index % regionPalette.count]
    }

    static let cornerResult: CGFloat = 12
    static let cornerPromptBar: CGFloat = 28
}

/// Botón de texto en mayúsculas con tracking (barra superior estilo FLUX Tools).
struct ToolTextButton: View {
    let icon: String
    let title: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(isActive ? Theme.border.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
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
