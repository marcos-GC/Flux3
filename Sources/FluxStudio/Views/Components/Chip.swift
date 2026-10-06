import SwiftUI

/// Chip de la barra de prompt (icono + texto).
struct Chip: View {
    let icon: String?
    let text: String
    var isActive = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
            }
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(isActive ? Theme.region.opacity(0.12) : Color.white.opacity(0.7)))
        .overlay(Capsule().strokeBorder(isActive ? Theme.region.opacity(0.5) : Theme.border, lineWidth: 1))
        .foregroundStyle(Theme.textPrimary)
        .contentShape(Capsule())
    }
}

/// Chip que abre una lista de opciones en un popover.
struct ChipPicker<Value: Hashable>: View {
    let icon: String?
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let label: (Value) -> String
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            Chip(icon: icon, text: label(selection))
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(title).padding(.horizontal, 10).padding(.bottom, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(options, id: \.self) { option in
                            Button {
                                selection = option
                                isOpen = false
                            } label: {
                                HStack {
                                    Text(label(option)).font(.system(size: 13))
                                    Spacer(minLength: 16)
                                    if option == selection {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(option == selection ? Theme.border.opacity(0.5) : .clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            .padding(10)
            .frame(minWidth: 180)
        }
    }
}
