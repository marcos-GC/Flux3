import FluxCore
import SwiftUI

/// Slider de `safety_tolerance` con valores enteros y etiquetas.
struct SafetyToleranceControl: View {
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                SectionLabel("Tolerancia de seguridad")
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .help(SafetyTolerance.tooltip)
                Spacer()
                Text("\(value) · \(SafetyTolerance.label(for: value, maximum: range.upperBound))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            ) {
                EmptyView()
            } minimumValueLabel: {
                Text("Estricto").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            } maximumValueLabel: {
                Text("Permisivo").font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
            }
            .help(SafetyTolerance.tooltip)
        }
        .onAppear { value = min(max(value, range.lowerBound), range.upperBound) }
        .onChange(of: range) { value = min(max(value, range.lowerBound), range.upperBound) }
    }
}
