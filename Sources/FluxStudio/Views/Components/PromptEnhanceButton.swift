import FluxCore
import SwiftUI

/// Botón «Mejorar»: reescribe el prompt con Claude Haiku según las guías de FLUX 3.
/// Muestra qué ha cambiado y permite deshacer.
struct PromptEnhanceButton: View {
    @EnvironmentObject private var state: AppState
    @Binding var text: String
    let context: () -> PromptEnhancer.Context

    @State private var isWorking = false
    @State private var previous: String?
    @State private var notes: String?
    @State private var showNotes = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: enhance) {
                HStack(spacing: 5) {
                    if isWorking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "wand.and.stars").font(.system(size: 11, weight: .medium))
                    }
                    Text(isWorking ? "Mejorando…" : "Mejorar").font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.region.opacity(0.12)))
                .overlay(Capsule().strokeBorder(Theme.region.opacity(0.5)))
                .foregroundStyle(Theme.textPrimary)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut("e", modifiers: .command)
            .help("Mejorar el prompt con Claude Haiku siguiendo las guías de FLUX 3 (⌘E)")
            .popover(isPresented: $showNotes, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Qué ha cambiado Claude")
                    Text(notes ?? "")
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    if previous != nil {
                        Button("Deshacer y volver a mi texto") { undo() }
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .padding(14)
                .frame(width: 300)
            }

            if previous != nil && !isWorking {
                Button { undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.7)))
                        .overlay(Circle().strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .help("Deshacer la mejora y volver a tu texto")
                if notes != nil {
                    Button { showNotes.toggle() } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Ver qué ha cambiado")
                }
            }
        }
        .onChange(of: text) {
            // Si el usuario escribe otra cosa, ya no tiene sentido deshacer la mejora.
            if !isWorking, let previous, text.isEmpty || text == previous {
                self.previous = nil
                notes = nil
            }
        }
        .onDisappear { task?.cancel() }
    }

    private func enhance() {
        let original = text
        let ctx = context()
        let key: String
        do {
            key = try state.settings.anthropicKey()
        } catch {
            state.alert = AppAlert(title: "Falta la API key de Anthropic", message: error.localizedDescription, opensSettings: true)
            return
        }
        isWorking = true
        task = Task {
            do {
                let result = try await PromptEnhancer.enhance(userPrompt: original, context: ctx, apiKey: key)
                // Si el usuario ha cambiado el texto mientras tanto, no lo pisamos.
                if text == original {
                    previous = original
                    notes = result.notes
                    text = result.prompt
                    showNotes = result.notes != nil
                }
            } catch is CancellationError {
            } catch {
                state.alert = AppAlert(title: "No se ha podido mejorar el prompt", message: error.localizedDescription)
            }
            isWorking = false
        }
    }

    private func undo() {
        guard let previous else { return }
        text = previous
        self.previous = nil
        notes = nil
        showNotes = false
    }
}
