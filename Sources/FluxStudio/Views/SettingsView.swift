import AppKit
import FluxCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var state: AppState

    @State private var keyInput = ""
    @State private var keyMessage: String?
    @State private var keyMessageIsError = false
    @State private var testing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Ajustes")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.top, 40)

                card {
                    SectionLabel("API key de Black Forest Labs")
                    HStack(spacing: 6) {
                        Image(systemName: settings.hasAPIKey ? "checkmark.seal.fill" : "exclamationmark.circle")
                            .foregroundStyle(settings.hasAPIKey ? Color.green : Theme.danger)
                        Text(settings.hasAPIKey ? "Hay una clave guardada en el Llavero." : "Todavía no hay ninguna clave guardada.")
                            .font(.system(size: 13))
                    }
                    SecureField("Pega aquí tu API key (dashboard.bfl.ai → API Keys)", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Guardar en el Llavero", action: saveKey)
                            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(action: testConnection) {
                            if testing {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Probar conexión")
                            }
                        }
                        .disabled(!settings.hasAPIKey || testing)
                        Spacer()
                        if settings.hasAPIKey {
                            Button("Borrar clave", role: .destructive) {
                                settings.deleteAPIKey()
                                show("Clave borrada del Llavero.", error: false)
                            }
                        }
                    }
                    if let keyMessage {
                        Text(keyMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(keyMessageIsError ? Theme.danger : Theme.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                card {
                    SectionLabel("Región de la API")
                    Picker("Región", selection: $settings.region) {
                        ForEach(APIRegion.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("EU guarda y procesa los datos en Europa. Global reparte la carga automáticamente.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                card {
                    SectionLabel("Archivos")
                    HStack {
                        Text(settings.outputFolder.path)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Mostrar") { revealOutputFolder() }
                        Button("Cambiar…") { chooseOutputFolder() }
                    }
                    Text("Cada resultado se guarda en una subcarpeta por día (AAAA-MM-DD) junto con un .json con sus parámetros.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Picker("Formato de salida por defecto", selection: $settings.defaultFormat) {
                        ForEach(OutputFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .frame(maxWidth: 340)
                    Text("Se usa en las herramientas que lo admiten (Outpainting, Borrar, Deblur, Probador). FLUX 3 Image elige el formato él solo.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }

                card {
                    SectionLabel("Valores por defecto")
                    SafetyToleranceControl(value: $settings.defaultSafety, range: 0...5)
                    Text("Si un modo admite menos (FLUX 3 Image y Vídeo: 0–4), se ajusta al máximo permitido.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                    Stepper(value: $settings.defaultImageCount, in: 1...4) {
                        Text("Número de imágenes por defecto: \(settings.defaultImageCount)")
                            .font(.system(size: 13))
                    }
                }

                card {
                    SectionLabel("Esta sesión")
                    Text("Créditos gastados: \(formatCredits(state.sessionCredits))")
                        .font(.system(size: 13))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceStyle(cornerRadius: 14)
    }

    private func show(_ text: String, error: Bool) {
        keyMessage = text
        keyMessageIsError = error
    }

    private func saveKey() {
        do {
            try settings.saveAPIKey(keyInput)
            keyInput = ""
            show("Clave guardada en el Llavero. Pulsa «Probar conexión» para comprobarla.", error: false)
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    private func testConnection() {
        testing = true
        Task {
            defer { testing = false }
            do {
                let client = try settings.makeClient()
                if let credits = try await client.credits() {
                    show("Conexión correcta con \(settings.region.displayName). Saldo: \(formatCredits(credits)) créditos.", error: false)
                } else {
                    show("Conexión correcta con \(settings.region.displayName).", error: false)
                }
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func revealOutputFolder() {
        try? FileManager.default.createDirectory(at: settings.outputFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([settings.outputFolder])
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.directoryURL = settings.outputFolder
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFolder = url
        }
    }
}
